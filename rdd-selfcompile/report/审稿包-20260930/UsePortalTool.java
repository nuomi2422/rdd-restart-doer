package com.dwinovo.numen.core.tools.interact;

import com.dwinovo.numen.agent.tool.NumenTool;
import com.dwinovo.numen.agent.tool.Schema;
import com.dwinovo.numen.core.task.interact.UsePortalTaskRecord;
import com.dwinovo.numen.entity.NumenPlayer;
import com.google.gson.Gson;
import com.google.gson.JsonObject;

import java.util.Map;
import java.util.function.Consumer;

import static com.dwinovo.numen.task.TaskDispatch.runSync;

/**
 * {@code use_portal}：找到最近的传送门，走过去，并真的走进去。
 *
 * <p><b>为什么需要它</b>（2026-09-29 实机）：在被传送门困住时，同伴会反复
 * {@code goto(block=minecraft:nether_portal)} —— 每次都"成功走到门旁"，
 * 然后发现自己还在原地维度、再来一次，无限循环。
 * {@code goto} 的契约是「走到旁边」，跨维度只有 USE 才触发。
 * 本工具把「找到 → 走过去 → 进去」合成一步。
 *
 * <p><b>用它的时机</b>：你<b>想换维度</b>时。在下界要回上界、上界要去下界、
 * 末地门同理。门是双向的，用当前维度的门就回另一维度。
 *
 * <p><b>它不做什么</b>：不搭门。要门就得先自己用黑曜石 + 打火石搭好并点燃
 * （{@code place_block} / {@code goto} + {@code interact_at}），然后本工具才找得到。
 */
public final class UsePortalTool implements NumenTool {

    private static final Gson GSON = new Gson();

    private record Args(String kind, Integer settle_ticks) {}

    @Override
    public String name() {
        return "use_portal";
    }

    @Override
    public String description() {
        return "GO THROUGH a portal — find the nearest one in the dimension you are in, walk to"
                + " it, and actually enter it. This is the ONLY way to change dimension: goto"
                + " does not work here, because goto stops BESIDE a block and a portal only"
                + " moves you when it is USED. Call this whenever you are in the wrong"
                + " dimension (in the nether and want home; overworld and want the nether;"
                + " anywhere and want the end). Portals are two-way: the one in this"
                + " dimension takes you back. It does NOT build a portal — if none exists"
                + " within range it says so; build one with 10 obsidian + flint and steel"
                + " first (place_block, then interact_at to light it), then call this again.";
    }

    @Override
    public Map<String, Object> parameterSchema() {
        return Schema.object()
                .enumStr("kind", "nether = nether portal (the way home / to the nether)."
                        + " end = end portal (to the end / back from it).",
                        "nether", "end")
                .nullableInteger("settle_ticks", "Ticks to stand beside the portal before"
                        + " entering. Use 20-40 right after lighting a NEW portal — it cannot be"
                        + " used for its first second. Null/0 = enter as soon as you arrive"
                        + " (right for an already-burning portal).")
                .build();
    }

    @Override
    public void onServerCall(String toolCallId, JsonObject args, NumenPlayer companion, Consumer<String> reply) {
        Args a = GSON.fromJson(args == null ? new JsonObject() : args, Args.class);
        String kind = a == null || a.kind() == null || a.kind().isBlank() ? "nether" : a.kind();
        int settle = a == null || a.settle_ticks() == null ? 0 : a.settle_ticks();
        UsePortalTaskRecord record = new UsePortalTaskRecord(
                toolCallId, System.currentTimeMillis() + 120_000, kind, settle);
        runSync(companion, record, reply);
    }
}
