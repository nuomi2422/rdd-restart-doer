package com.dwinovo.numen.rdd.core;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

/**
 * 死亡台账：每一次死亡单独一行，带掉落物到期时刻。
 *
 * <p>这些断言锁的是用户 2026-09-29 报的两个真 bug：
 * ①「他以为自己的东西已经没有了」——死亡后 5 分钟内掉落物**还在地上**，
 * 但旧实现只发"失效 N 项"，没有任何人告诉她还剩多少秒；
 * ②「死多次就分不清」——实机 15:50:53 死在 (200,51,-130)、15:51:09 又死在
 * (134,31,-96)，相隔 16 秒，两个掉落点的到期时刻不同。
 */
class RddDeathLedgerTest {

    private UUID id;

    @BeforeEach void setUp() {
        RddDeathLedger.clearAll();
        id = UUID.randomUUID();
    }

    @Test void nothingRecordedMeansNothingToRecover() {
        assertEquals(0, RddDeathLedger.deathsRecorded(id));
        assertNull(RddDeathLedger.latest(id));
        assertTrue(RddDeathLedger.render(id, 1000L).contains("no death recorded"));
    }

    @Test void dropsAreStillRecoverableForFiveMinutes() {
        var d = RddDeathLedger.record(id, 1000L, System.currentTimeMillis(), "200, 51, -130", 29);
        assertEquals(1, d.seq());
        assertEquals("200, 51, -130", d.deathAt());
        assertTrue(d.stillRecoverable(1000L));
        assertEquals(300, d.secondsLeft(1000L), "刚死就该有 5 分钟 = 300 秒");
        // 4 分 59 秒：还在
        assertTrue(d.stillRecoverable(1000L + (20 * 60 * 4) + 19));
        // 正好 5 分钟：过期（与原版 despawn 同口径）
        assertFalse(d.stillRecoverable(1000L + RddDeathLedger.DROPS_LIVE_TICKS));
        assertEquals(0, d.ticksLeft(1000L + RddDeathLedger.DROPS_LIVE_TICKS));
    }

    @Test void twoDeathsSixteenSecondsApartKeepSeparateCountdowns() {
        // 实机原样复现：15:50:53 与 15:51:09，相隔 16 秒（320 tick）
        var first = RddDeathLedger.record(id, 1000L, 0L, "200, 51, -130", 29);
        var second = RddDeathLedger.record(id, 1320L, 0L, "134, 31, -96", 29);
        assertEquals(1, first.seq());
        assertEquals(2, second.seq(), "序号必须递增，否则分不清哪一次是哪一次");

        // 过 50 秒（2000 tick）：第一次还剩 250 秒，第二次还剩 266 秒
        long now = 2000L;
        assertEquals(250, first.secondsLeft(now));
        assertEquals(266, second.secondsLeft(now));
        assertEquals(2, RddDeathLedger.recoverable(id, now).size());

        // 过 100 秒（7000 tick）：第一次刚好满 5 分钟已过期，第二次还剩 16 秒
        now = 7000L;
        assertFalse(first.stillRecoverable(now));
        assertTrue(second.stillRecoverable(now));
        assertEquals(1, RddDeathLedger.recoverable(id, now).size());
        assertEquals(1, RddDeathLedger.expired(id, now).size());
    }

    @Test void recoverableIsOrderedSoTheMostUrgentComesFirst() {
        RddDeathLedger.record(id, 1000L, 0L, "A", 5);
        RddDeathLedger.record(id, 2000L, 0L, "B", 5);
        var live = RddDeathLedger.recoverable(id, 2500L);
        assertEquals(2, live.size());
        assertEquals("A", live.get(0).deathAt(), "先捡最先过期的那个");
        assertEquals("B", live.get(1).deathAt());
    }

    @Test void renderTellsHerToGoWhenThereIsTimeAndToStopWhenThereIsNot() {
        // 有窗口：必须给出坐标 + 倒计时，否则她就按"东西没了"重新规划
        RddDeathLedger.record(id, 1000L, 0L, "200, 51, -130", 29);
        var live = RddDeathLedger.render(id, 2000L);
        assertTrue(live.contains("200, 51, -130"), live);
        assertTrue(live.contains("despawns in 250s"), live);
        assertTrue(live.contains("still on the ground"), live);

        // 全过期：必须**明确叫停**——这是旧实现最缺的一句（旧版只会一直催她白跑）
        var gone = RddDeathLedger.render(id, 1000L + RddDeathLedger.DROPS_LIVE_TICKS + 1);
        assertTrue(gone.contains("Do NOT go back"), gone);
        assertTrue(gone.contains("permanently gone"), gone);
    }

    @Test void renderExplainsWhichOfTwoToDoFirst() {
        RddDeathLedger.record(id, 1000L, 0L, "A", 5);
        RddDeathLedger.record(id, 1320L, 0L, "B", 5);
        var r = RddDeathLedger.render(id, 2000L);
        assertTrue(r.contains("2 death drop(s) still on the ground"), r);
        assertTrue(r.contains("NEAREST one first"), r);
    }

    @Test void ledgerIsBoundedSoACrashLoopCannotInflateThePayload() {
        for (int i = 0; i < RddDeathLedger.MAX_ENTRIES * 3; i++) {
            RddDeathLedger.record(id, 1000L + i * 20L, 0L, "P" + i, 1);
        }
        assertEquals(RddDeathLedger.MAX_ENTRIES, RddDeathLedger.deathsRecorded(id));
        // 保留的是最新的那几条
        assertEquals("P" + (RddDeathLedger.MAX_ENTRIES * 3 - 1),
                RddDeathLedger.latest(id).deathAt());
    }

    @Test void ledgersArePerCompanionAndClearable() {
        UUID a = UUID.randomUUID(), b = UUID.randomUUID();
        RddDeathLedger.record(a, 1L, 0L, "A1", 1);
        RddDeathLedger.record(b, 1L, 0L, "B1", 1);
        assertEquals(1, RddDeathLedger.deathsRecorded(a));
        assertEquals(1, RddDeathLedger.deathsRecorded(b));
        RddDeathLedger.clear(a);
        assertEquals(0, RddDeathLedger.deathsRecorded(a));
        assertEquals(1, RddDeathLedger.deathsRecorded(b), "清一个不能连带清另一个");
    }
}
