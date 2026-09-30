package com.dwinovo.numen.rdd.core;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 死亡台账：<b>每一次死亡单独一行，带掉落物的到期时刻</b>。
 *
 * <h2>为什么要有（2026-09-29 实机）</h2>
 * 旧实现只在死亡瞬间发一条 {@code companion_assets_invalidated}{count}，
 * 于是产生两个真 bug：
 * <ol>
 *   <li><b>它以为东西已经没了</b>：死亡后 5 分钟内掉落物<b>还在地上</b>，
 *       但资产已被标失效，没有任何人告诉它"还剩 200 秒，快去捡" →
 *       它按"东西没了"重新规划。</li>
 *   <li><b>连死两次就分不清了</b>：实机 15:50:53 死在 (200,51,-130)，
 *       15:51:09 又死在 (134,31,-96)，相隔 16 秒。两个掉落点的到期时刻不同，
 *       旧实现只留"最后一条"，于是"哪一次的掉落已经过期"根本无法回答。</li>
 * </ol>
 *
 * <h2>时间基准</h2>
 * 掉落物 despawn 按<b>游戏时间</b>，不是墙钟 —— 退出重进世界不加载时游戏时间不前进，
 * 掉落物也就不会消失。本类因此同时记 {@code gameTime}（用于到期判定，与原版同口径）
 * 和 {@code wallClockMillis}（仅供人看/排序）。到期判定只认 gameTime。
 *
 * <h2>有界</h2>
 * 每个同伴最多留 {@link #MAX_ENTRIES} 条（默认 8），按 gameTime 淘汰最老的。
 * 理由：连续死亡是常态，无界增长会让监测台 payload 膨胀到没法看。
 */
public final class RddDeathLedger {

    /**
     * 原版掉落物 despawn 时长：<b>5 分钟</b>。
     *
     * <p>必须是 {@code 20 tick/s * 60 s * 5 min = 6000}。第一版误写成
     * {@code 20 * 60}（=1200 tick = 1 分钟），单测直接量出 "还剩 60 秒" 才发现 ——
     * 窗口缩水到 1/5，她会在还有 4 分钟的时候就以为东西没了。
     */
    public static final long DROPS_LIVE_TICKS = 20L * 60L * 5L;

    /** 每个同伴保留的死亡记录条数上限（连续死亡是常态，无界会让 payload 膨胀）。 */
    public static final int MAX_ENTRIES = 8;

    /** 一次死亡。字段全 final：记录一经写下就不该被"修正"。 */
    public record Death(int seq, long gameTime, long wallClockMillis,
                        String deathAt, int lostEntries) {

        /** 这一次的掉落物在 {@code nowGameTime} 时是否还该在地上。 */
        public boolean stillRecoverable(long nowGameTime) {
            return nowGameTime - gameTime < DROPS_LIVE_TICKS;
        }

        /** 距离 despawn 还有多少 tick（已过期返回 0）。 */
        public long ticksLeft(long nowGameTime) {
            long left = DROPS_LIVE_TICKS - (nowGameTime - gameTime);
            return Math.max(0, left);
        }

        public long secondsLeft(long nowGameTime) {
            return ticksLeft(nowGameTime) / 20L;
        }
    }

    private static final Map<UUID, List<Death>> LEDGER = new ConcurrentHashMap<>();
    private static final Map<UUID, Integer> SEQ = new ConcurrentHashMap<>();

    private RddDeathLedger() {}

    /**
     * 记一次死亡，返回新写入的那条。
     *
     * <p>{@code gameTime} 用 RddInstrumentation 的游戏时间（与 despawn 同口径）；
     * 传负数表示"读不到游戏时间"，此时本条不参与到期判定（{@code ticksLeft} 恒为满窗），
     * 免得用墙钟去猜一个和原版不同口径的时钟。
     */
    public static Death record(UUID companionId, long gameTime, long wallClockMillis,
                               String deathAt, int lostEntries) {
        UUID id = companionId == null ? new UUID(0, 0) : companionId;
        int seq = SEQ.merge(id, 1, Integer::sum);
        Death d = new Death(seq, gameTime, wallClockMillis,
                deathAt == null ? "?" : deathAt, Math.max(0, lostEntries));
        List<Death> list = LEDGER.computeIfAbsent(id, k -> new ArrayList<>());
        synchronized (list) {
            list.add(d);
            while (list.size() > MAX_ENTRIES) {
                list.remove(0);
            }
        }
        return d;
    }

    /** 全部记录，最新在前。 */
    public static List<Death> all(UUID companionId) {
        List<Death> list = LEDGER.get(companionId);
        if (list == null) return List.of();
        synchronized (list) {
            List<Death> copy = new ArrayList<>(list);
            copy.sort(Comparator.comparingLong(Death::gameTime).reversed());
            return List.copyOf(copy);
        }
    }

    /** 掉落物还在地上的那些（按到期时刻从早到晚排：先捡最先过期的）。 */
    public static List<Death> recoverable(UUID companionId, long nowGameTime) {
        List<Death> out = new ArrayList<>();
        for (Death d : all(companionId)) {
            if (d.stillRecoverable(nowGameTime)) out.add(d);
        }
        out.sort(Comparator.comparingLong(Death::gameTime));
        return List.copyOf(out);
    }

    /** 已经过期的（真正"没了"的那些）。 */
    public static List<Death> expired(UUID companionId, long nowGameTime) {
        List<Death> out = new ArrayList<>();
        for (Death d : all(companionId)) {
            if (!d.stillRecoverable(nowGameTime)) out.add(d);
        }
        return List.copyOf(out);
    }

    /** 最近一条；没有则 null。 */
    public static Death latest(UUID companionId) {
        List<Death> a = all(companionId);
        return a.isEmpty() ? null : a.get(0);
    }

    /** 死亡次数（台账内计数）。 */
    public static int deathsRecorded(UUID companionId) {
        return all(companionId).size();
    }

    /**
     * 渲染成一句话交给规划器/执行层。
     *
     * <p>空台账说"没死过"；全部过期明确说"别白跑一趟"——这是旧实现最缺的一句：
     * 旧实现只会催她去捡，捡不到就再规划一次、再撞一次。
     */
    public static String render(UUID companionId, long nowGameTime) {
        List<Death> a = all(companionId);
        if (a.isEmpty()) {
            return "no death recorded — nothing to recover";
        }
        List<Death> live = recoverable(companionId, nowGameTime);
        StringBuilder sb = new StringBuilder();
        if (live.isEmpty()) {
            sb.append(a.size()).append(" death record(s), ALL of their drops have already despawned")
              .append(" (>").append(DROPS_LIVE_TICKS / 20).append("s old). Do NOT go back for them —")
              .append(" treat those items as permanently gone and plan without them.");
            return sb.toString();
        }
        sb.append(live.size()).append(" death drop(s) still on the ground (of ")
          .append(a.size()).append(" recorded):");
        for (int i = 0; i < live.size(); i++) {
            Death d = live.get(i);
            sb.append("\n  #").append(d.seq()).append(' ').append(d.deathAt())
              .append(" — ").append(d.lostEntries()).append(" items, despawns in ")
              .append(d.secondsLeft(nowGameTime)).append('s');
        }
        if (live.size() > 1) {
            sb.append("\nGo to the NEAREST one first — the later ones have more time left.");
        }
        return sb.toString();
    }
    /** 清掉某同伴的台账（任务重置/世界重载时用，免得把上一局的死算进这一局）。 */
    public static void clear(UUID companionId) {
        LEDGER.remove(companionId);
        SEQ.remove(companionId);
    }

    public static void clearAll() {
        LEDGER.clear();
        SEQ.clear();
    }
}
