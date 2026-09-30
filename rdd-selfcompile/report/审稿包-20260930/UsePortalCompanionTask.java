package com.dwinovo.numen.core.task.interact;

import com.dwinovo.numen.core.Constants;
import com.dwinovo.numen.core.FailureType;
import com.dwinovo.numen.core.pathing.execute.PlayerNav;
import com.dwinovo.numen.core.pathing.goal.GoalCompiler;
import com.dwinovo.numen.core.pathing.util.BlockHelper;
import com.dwinovo.numen.core.scan.BlockScanner;
import com.dwinovo.numen.core.scan.BlockSearch;
import com.dwinovo.numen.core.task.base.AbstractCompanionTask;
import com.dwinovo.numen.entity.NumenPlayer;
import com.dwinovo.numen.task.TaskState;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.NetherPortalBlock;
import net.minecraft.world.phys.BlockHitResult;

import java.util.List;
import java.util.Set;

/**
 * 走到最近的传送门并 USE 它——真正完成一次跨维度。
 *
 * <p>形状：扫描（{@link BlockSearch}，与 {@code goto} 的 FIND / {@code scan_blocks}
 * 同一条路）→ 寻路走到门旁 → 静置 {@link UsePortalTaskRecord#settleTicks} → USE。
 *
 * <p><b>为什么不能只靠 goto</b>（2026-09-29 实机）：goto 的契约是「走到旁边」，
 * 它停在门旁就宣告完成；而跨维度只有 USE 才触发。症状是同伴在门前来回重复
 * {@code goto(block=minecraft:nether_portal)}，永远出不去。
 *
 * <p><b>为什么静置</b>：原版传送门被点燃后有 0.8 秒（16 tick）不可用，
 * 立刻 USE 会被原版静默吞掉——表现为「我按了但没反应」，模型于是反复重试。
 */
public final class UsePortalCompanionTask extends AbstractCompanionTask<UsePortalTaskRecord> {

    /** 搜索半径（格）。门不会在更远的地方有意义。 */
    private static final int SEARCH_RADIUS = 96;
    /** 要几个候选：最近那个可能已被点燃过/被岩浆糊掉，留备胎。 */
    private static final int WANT = 4;
    /**
     * 进门判据：身体<b>真的站进了门块里</b>。
     *
     * <p>2026-09-29 实机修正：我第一版是"走到门旁 + USE 一次"。实测
     * {@code use_portal USED portal at 59,56,-43 ... result=PASS}，同伴站在
     * (62,46,-43) 满血吃饭，<b>人还在下界</b>。原因：原版下界传送门
     * <b>不能被 USE</b> —— 它不是可交互方块，{@code use()} 直接 PASS；
     * 真正的传送发生在实体<b>走进门块</b>时（{@code NetherPortalBlock.entityInside}
     * → {@code PortalShape} 安排延迟传送）。所以本任务的重点是
     * <b>把人送进那个方块里，然后等原版做它的事</b>，不需要也不该自己调 use。
     */
    private static final double WALK_SPEED = 1.0;
    /** 走进门里之后，原版要几 tick 才把坐标换算到另一维度。 */
    private static final int VANILLA_TELEPORT_TICKS = 90;
    private static final long USE_COOLDOWN_MS = 1200;
    /** 门消失后重扫的上限，防止「门被人反复拆了」时无限重扫。 */
    private static final int MAX_RESCANS = 3;
    /** 站进门前最多等这么久：进不去要报错，不能无限占着身体（单驾驶员铁律）。 */
    private static final int ENTER_TIMEOUT_TICKS = 200;

    private final UsePortalTaskRecord rec;
    private final Block target;
    private final ResourceKey<Level> startDim;

    private int scanId;
    private List<BlockScanner.Hit> hits;
    private BlockPos door;
    private int rescans;
    /** 找到门那一刻的 gameTime：用来兜底"进不去"与"进去了没传送"两种超时。 */
    private long enterSince;
    private long insideSince;
    private long settleUntil;

    public UsePortalCompanionTask(NumenPlayer player, UsePortalTaskRecord record) {
        super(player, record);
        this.rec = record;
        this.target = BuiltInRegistries.BLOCK.get(
                net.minecraft.resources.ResourceLocation.parse(record.targetBlock()));
        this.startDim = player.level().dimension();
    }

    @Override
    protected void onStart() {
        kickScan();
        Constants.LOG.info("[numen-task] use_portal start kind={} in {} target={}",
                rec.kind, startDim.location(), rec.targetBlock());
    }

    private void kickScan() {
        if (!(player.level() instanceof ServerLevel level)) {
            fail("no server level for portal search", FailureType.UNKNOWN);
            return;
        }
        var feet = BlockHelper.playerFeet(level, player.getX(), player.getY(), player.getZ());
        scanId = BlockSearch.start(player.getUUID(), level, feet, SEARCH_RADIUS, WANT,
                Set.of(target), res -> {
                    scanId = 0;
                    hits = res.matches();
                });
    }

    @Override
    protected TaskState onTick() {
        // 已经进了另一维度 → 收工
        if (player.level().dimension() != startDim) {
            return TaskState.SUCCESS;
        }
        if (door == null) {
            if (scanId == 0 && hits == null) {
                fail(noPortalHere(), FailureType.UNKNOWN);
                return TaskState.FAILED;
            }
            if (hits != null) {
                hits.stream()
                        .sorted((a, b) -> Double.compare(a.distance(), b.distance()))
                        .map(h -> h.pos().immutable())
                        .findFirst()
                        .ifPresent(p -> door = p);
                hits = null;
            }
            if (door == null) return TaskState.RUNNING;
            enterSince = player.level().getGameTime();
            Constants.LOG.info("[numen-task] use_portal found portal at {} (walk INTO it, not use it)",
                    door.toShortString());
        }
        if (door == null || !stillPortal()) {
            return lostPortal();
        }
        if (insidePortal()) {
            // 站进去了。剩下的交给原版：entityInside → PortalShape 会在几十 tick 后换维度。
            if (player.level().getGameTime() - enterSince > VANILLA_TELEPORT_TICKS + ENTER_TIMEOUT_TICKS) {
                fail("standing inside the portal at " + door.toShortString() + " for "
                        + (VANILLA_TELEPORT_TICKS + ENTER_TIMEOUT_TICKS) + " ticks and it did not"
                        + " move me. A nether portal needs a matching one on the other side, and"
                        + " it is usually built from obsidian — check with inspect_block that this"
                        + " frame is obsidian and complete (a 4x5 minimum frame, no missing corners).",
                        FailureType.UNKNOWN);
                return TaskState.FAILED;
            }
            if (player.level().getGameTime() < settleUntil) {
                return TaskState.RUNNING;   // 门前静置，等门就绪
            }
            insideSince = insideSince == 0 ? player.level().getGameTime() : insideSince;
            return TaskState.RUNNING;      // 等原版传送
        }
        if (player.level().getGameTime() - enterSince > ENTER_TIMEOUT_TICKS) {
            fail("could not walk into the portal at " + door.toShortString()
                    + " — it stays just out of reach. mine/break whatever blocks it, or build a"
                    + " fresh frame with 10 obsidian and flint&steel next to you.", FailureType.OUT_OF_REACH);
            return TaskState.FAILED;
        }
        return walkToward(door);
    }

    /** 身体是不是真的站在门块里（原版传送的唯一触发条件）。 */
    private boolean insidePortal() {
        var under = player.blockPosition();
        if (under.equals(door)) {
            return player.level().getBlockState(under).getBlock() instanceof NetherPortalBlock;
        }
        // 门是竖井，站进去时脚可能在门格或紧邻的空气格；两者都算"进去了"
        for (var d : new net.minecraft.core.Direction[]{
                net.minecraft.core.Direction.UP, net.minecraft.core.Direction.DOWN,
                net.minecraft.core.Direction.NORTH, net.minecraft.core.Direction.SOUTH,
                net.minecraft.core.Direction.EAST, net.minecraft.core.Direction.WEST}) {
            var p = under.relative(d);
            if (p.equals(door) && player.level().getBlockState(p).getBlock() instanceof NetherPortalBlock) {
                return true;
            }
        }
        return false;
    }

    private boolean stillPortal() {
        return player.level().getBlockState(door).getBlock() instanceof NetherPortalBlock;
    }

    /** 门被拆/被熄：重扫，但有上限。 */
    private TaskState lostPortal() {
        Constants.LOG.warn("[numen-task] use_portal: {} is no longer a burning portal", door.toShortString());
        if (++rescans > MAX_RESCANS) {
            fail("found a portal at " + door.toShortString() + " but it stopped being one after "
                    + rescans + " rescans (someone is breaking it, or lava is dousing it)."
                    + " Build a fresh one with 10 obsidian and flint&steel, wait for it to"
                    + " light, then call this again.", FailureType.UNKNOWN);
            return TaskState.FAILED;
        }
        stopNav();
        door = null;
        hits = null;
        insideSince = 0;
        kickScan();
        return TaskState.RUNNING;
    }

    private String noPortalHere() {
        return "no " + rec.targetBlock() + " within " + SEARCH_RADIUS + " blocks in "
                + startDim.location() + ". A portal only exists where someone built it — in the"
                + " nether it is your way HOME, so you must already be in the nether with the"
                + " portal you came in through. get_world_info shows which dimension you are in.";
    }

    private TaskState driveNav() {
        return switch (nav.tick()) {
            case RUNNING -> TaskState.RUNNING;
            case ARRIVED -> {
                stopNav();
                settleUntil = player.level().getGameTime() + rec.settleTicks;
                yield TaskState.RUNNING;
            }
            case FAILED -> {
                String why = nav.failReason();
                stopNav();
                // 已经站到门里了就别被寻路口径判死 —— 传送已经发生或即将发生
                if (insidePortal()) {
                    yield TaskState.RUNNING;
                }
                fail("could not walk into the portal at " + door.toShortString() + ": " + why,
                        FailureType.NO_PATH);
                yield TaskState.FAILED;
            }
        };
    }

    /**
     * 走进门块里（不是停在旁边）。
     *
     * <p>用 TERRAFORM 允许开路：下界门常被岩浆/方块围着，不开路就站不进去；
     * 目标格由 {@code standOn} 标成 sacred，路线不会把门本身挖掉。
     */
    private TaskState walkToward(BlockPos p) {
        var compiled = GoalCompiler.standOn(p);
        nav = PlayerNav.to(player, () -> compiled, WALK_SPEED, this::insidePortal,
                PlayerNav.ContextProvider.TERRAFORM);
        return TaskState.RUNNING;
    }

    @Override
    protected void cleanup() {
        super.cleanup();
        if (scanId != 0) {
            BlockSearch.cancel(scanId);
            scanId = 0;
        }
    }

    @Override
    protected String successMessage() {
        return "went through the portal at " + (door == null ? "?" : door.toShortString());
    }
}
