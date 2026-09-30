package com.dwinovo.numen.rdd.policy;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * 风险门文本分级的否定约束回归（2026-09-28）。
 *
 * <p><b>真机踩坑原文</b>（安身立命链 primary-6 的真实描述）：
 * 「待命：确认据点/重生点正常、整套铁甲与装备在手、箱中20铁锭储备到位后原地待命，不再向外推进，
 * <b>也绝不进入下界</b>。」
 *
 * <p>旧实现只看动词窗口里有没有「进入」，于是把这条**禁止项**当成"要去下界"
 * → 判 NETHER → 给这个「原地待命」阶段挂上下界准备硬门 → 每秒一条 primary_waiting，
 * 任务永远派不下去（实测连发 92 秒，AI 完全没活干）。
 */
class RiskGateNegationTest {

    private static final String REAL_PRIMARY6 =
            "待命：确认据点/重生点正常、整套铁甲与装备在手、箱中20铁锭储备到位后原地待命，不再向外推进，也绝不进入下界。";

    @Test void realPrimary6IsNotNetherGated() {
        assertEquals(RiskLevel.NORMAL, RiskGate.levelForText(REAL_PRIMARY6));
    }

    @Test void positiveNetherIntentStillGated() {
        // 收紧不能过头：真要去下界仍然必须被门拦住
        assertEquals(RiskLevel.NETHER, RiskGate.levelForText("进入下界采集下界合金"));
        assertEquals(RiskLevel.NETHER, RiskGate.levelForText("前往下界建立据点"));
        assertEquals(RiskLevel.NETHER, RiskGate.levelForText("下界探索与筹备物资"));
    }

    @Test void negationVariantsAllCountAsProhibition() {
        for (String t : new String[]{
                "不进入下界", "不再进入下界", "不要前往末地", "避免进入下界",
                "禁止进入下界", "别去下界", "无需进入下界", "不用探索末地"}) {
            assertEquals(RiskLevel.NORMAL, RiskGate.levelForText(t), t);
        }
    }

    @Test void endIntentStillGated() {
        assertEquals(RiskLevel.END, RiskGate.levelForText("击杀末影龙"));
        assertEquals(RiskLevel.END, RiskGate.levelForText("挑战末地"));
    }

    @Test void miningAndNormalUnaffected() {
        assertEquals(RiskLevel.MINING, RiskGate.levelForText("下矿挖矿采集铁矿"));
        assertEquals(RiskLevel.NORMAL, RiskGate.levelForText("建据点、抢占床并绑定重生点"));
    }
}
