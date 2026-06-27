# AMD Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ICT AMD (Accumulation / Manipulation / Distribution) detection and rendering to VP_MultiTF_Suite.mq5, with 3 detection modes and 3 confirmation levels, all user-configurable.

**Architecture:** Single-file modification. AMD logic is fully self-contained — new enums, struct, globals, and 2 new functions (CalcAMD + RenderAMD) plugged into the existing OnCalculate pipeline after VP rendering. No new files created.

**Tech Stack:** MQL5 / MetaTrader 5. No external dependencies. Compile with MetaEditor (F7).

## Global Constraints

- File: `C:\Users\Pandara Actor\AppData\Roaming\MetaQuotes\Terminal\B9CD1E3322764DD9E8845B7C56122B7D\MQL5\Indicators\VP_MultiTF_Suite.mq5`
- Spec: `D:\WEB Trading.Journal\docs\superpowers\specs\2026-06-18-amd-feature-design.md`
- Version must be bumped to `"4.00"` in `#property version`
- Object prefix for all AMD objects: `g_pfx + "AMD_"` (g_pfx is already `"VPMTF_"`)
- Arrays use `ArraySetAsSeries(R, true)` — R[0] is the newest bar
- No compound literal syntax `(Struct){...}` — MQL5 does not support it; always declare var then assign fields
- Compile must show **0 errors, 0 warnings** before each commit
- Each task ends with a MetaEditor compile check

---

### Task 1: Add Enums, AMDRec Struct, and Globals

**Files:**
- Modify: `VP_MultiTF_Suite.mq5` — TYPES section (after existing enums ~line 54) and GLOBALS section (~line 78)

**Interfaces:**
- Produces: `EAMD_MODE`, `EAMD_CONF` enums; `AMDRec` struct; `g_amd[10]`, `g_nAMD`, `g_amdDirty` globals — used by Tasks 3–6

- [ ] **Step 1: Add enums after existing EVPS/EVPB enums (~line 55)**

Insert after `enum EVPB { VPB_RNG=0, VPB_BULL=1, VPB_BEAR=2 };`:

```mql5
enum EAMD_MODE { AMD_SESSION=0, AMD_SWING=1, AMD_MANUAL=2 };
enum EAMD_CONF { CONF_PRIMARY=0, CONF_SECONDARY=1, CONF_TERTIARY=2 };
```

- [ ] **Step 2: Add AMDRec struct after TFRec and VPLine structs (~line 74)**

Insert after the closing `};` of `struct VPLine`:

```mql5
struct AMDRec {
   datetime dateKey;
   double   accumHi;
   double   accumLo;
   datetime accumStart;
   datetime accumEnd;
   int      manipDir;      // +1=swept highs(→bear), -1=swept lows(→bull), 0=none
   double   manipExtreme;
   datetime manipTime;
   double   distTarget;
   int      confLevel;     // 0=none,1=primary,2=secondary,3=tertiary
};
```

- [ ] **Step 3: Add AMD globals after existing globals (~line 89)**

Insert after `double g_pip;`:

```mql5
AMDRec g_amd[10];
int    g_nAMD    = 0;
bool   g_amdDirty = false;
```

- [ ] **Step 4: Compile in MetaEditor (F7)**

Expected: `VP_MultiTF_Suite.mq5  0 errors, 0 warnings`

- [ ] **Step 5: Commit**

```bash
git add "C:/Users/Pandara Actor/AppData/Roaming/MetaQuotes/Terminal/B9CD1E3322764DD9E8845B7C56122B7D/MQL5/Indicators/VP_MultiTF_Suite.mq5"
git commit -m "feat(amd): add AMDRec struct, enums, globals"
```

---

### Task 2: Add AMD Input Groups

**Files:**
- Modify: `VP_MultiTF_Suite.mq5` — INPUTS section (~line 17)

**Interfaces:**
- Consumes: `EAMD_MODE`, `EAMD_CONF` enums from Task 1
- Produces: All `InpAMD*` input variables — used by CalcAMD (Task 3–4) and RenderAMD (Task 5)

- [ ] **Step 1: Add AMD Settings input group after `── Display ──` group (~line 49)**

Insert after the last `input` in the Display group:

```mql5
input group "── AMD Settings ──"
input bool      InpAMDShow      = true;
input EAMD_MODE InpAMDMode      = AMD_SESSION;
input int       InpAMDGMTOff    = 0;
input int       InpAMDAsiaStart = 0;
input int       InpAMDAsiaEnd   = 8;
input int       InpAMDLonStart  = 8;
input int       InpAMDLonEnd    = 13;
input int       InpAMDLookback  = 3;
input color     InpAccumClr     = C'40,60,80';
input color     InpManipClr     = clrOrangeRed;
input color     InpDistClr      = clrLimeGreen;

input group "── AMD Confirmation ──"
input EAMD_CONF InpAMDConf     = CONF_PRIMARY;
input int       InpVolAvgBars  = 20;
input double    InpVolSpikeMin = 1.5;
```

- [ ] **Step 2: Compile in MetaEditor (F7)**

Expected: `0 errors, 0 warnings`

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(amd): add AMD input groups"
```

---

### Task 3: Implement CalcAMD() — Accumulation Detection

**Files:**
- Modify: `VP_MultiTF_Suite.mq5` — add helper functions and CalcAMD() before `OnDeinit` (~line 122)

**Interfaces:**
- Consumes: `g_tf[]`, `g_nTF`, `InpAMDMode`, `InpAMDGMTOff`, `InpAMDAsiaStart/End`, `InpAMDLookback`
- Produces: `g_amd[]` with `dateKey`, `accumHi`, `accumLo`, `accumStart`, `accumEnd` populated; `g_nAMD` set; `g_amdDirty = true` when changed

- [ ] **Step 1: Add FindSwingTFIdx() helper**

Insert before `OnDeinit`:

```mql5
// Returns the best TF index for SWING mode: D1 > H4 > highest active
int FindSwingTFIdx() {
   int bestD1=-1, bestH4=-1, bestAny=-1;
   for(int i=0; i<g_nTF; i++) {
      if(!g_tf[i].on || g_tf[i].poc==0.0) continue;
      if(g_tf[i].tf==PERIOD_D1) bestD1=i;
      if(g_tf[i].tf==PERIOD_H4) bestH4=i;
      bestAny=i;
   }
   if(bestD1>=0) return bestD1;
   if(bestH4>=0) return bestH4;
   return bestAny;
}
```

- [ ] **Step 2: Add HourFromTime() helper**

```mql5
int HourFromTime(datetime t) {
   MqlDateTime s; TimeToStruct(t, s); return s.hour;
}

datetime TruncDay(datetime t) {
   MqlDateTime s; TimeToStruct(t, s);
   s.hour=0; s.min=0; s.sec=0;
   return StructToTime(s);
}
```

- [ ] **Step 3: Add CalcAMD() — accumulation phase only**

```mql5
void CalcAMD() {
   if(!InpAMDShow) return;

   // Copy enough M1 bars: lookback days * 1440 bars/day + buffer
   int need = InpAMDLookback * 1440 + 200;
   MqlRates R[];
   ArraySetAsSeries(R, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 0, need, R);
   if(copied < 2) return;

   // GMT offset adjustment in seconds
   int gmt_sec = InpAMDGMTOff * 3600;

   // Build one AMDRec per day, from newest to oldest
   g_nAMD = 0;
   datetime today = TruncDay(R[0].time - gmt_sec);

   for(int d = 0; d < InpAMDLookback && g_nAMD < 10; d++) {
      datetime dayStart = today - (datetime)(d * 86400);
      datetime dayEnd   = dayStart + 86400;

      AMDRec rec;
      ZeroMemory(rec);
      rec.dateKey = dayStart;
      rec.accumHi = -DBL_MAX;
      rec.accumLo =  DBL_MAX;
      rec.accumStart = 0;
      rec.accumEnd   = 0;

      if(InpAMDMode == AMD_SWING) {
         int idx = FindSwingTFIdx();
         if(idx < 0) { g_nAMD++; g_amd[g_nAMD-1]=rec; continue; }
         rec.accumHi    = g_tf[idx].hi;
         rec.accumLo    = g_tf[idx].lo;
         rec.accumStart = dayStart;
         rec.accumEnd   = dayStart + (datetime)(InpAMDAsiaEnd * 3600);
      } else {
         // SESSION or MANUAL: scan M1 bars in Asia window
         int asiaStartH = InpAMDAsiaStart;
         int asiaEndH   = InpAMDAsiaEnd;
         for(int b = 0; b < copied; b++) {
            datetime bt = R[b].time - gmt_sec;
            if(bt < dayStart || bt >= dayEnd) continue;
            int hr = HourFromTime(bt);
            if(hr < asiaStartH || hr >= asiaEndH) continue;
            if(rec.accumStart == 0) rec.accumStart = R[b].time;
            rec.accumEnd = R[b].time + 60;
            if(R[b].high > rec.accumHi) rec.accumHi = R[b].high;
            if(R[b].low  < rec.accumLo) rec.accumLo = R[b].low;
         }
      }

      if(rec.accumHi == -DBL_MAX || rec.accumHi <= rec.accumLo + _Point*2) {
         // Not enough data — store empty record
         rec.accumHi = 0; rec.accumLo = 0;
      }

      g_amd[g_nAMD++] = rec;
   }
   g_amdDirty = true;
}
```

- [ ] **Step 4: Compile in MetaEditor (F7)**

Expected: `0 errors, 0 warnings`

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(amd): CalcAMD accumulation detection"
```

---

### Task 4: Add Manipulation + Confirmation Detection to CalcAMD()

**Files:**
- Modify: `VP_MultiTF_Suite.mq5` — extend CalcAMD() and add helpers

**Interfaces:**
- Consumes: `g_amd[]` with accumulation data from Task 3; `InpAMDConf`, `InpVolAvgBars`, `InpVolSpikeMin`, `InpAMDLonStart/End`
- Produces: `g_amd[].manipDir`, `manipExtreme`, `manipTime`, `distTarget`, `confLevel` populated

- [ ] **Step 1: Add AvgVolume() helper — used for Secondary confirmation**

Insert before CalcAMD():

```mql5
double AvgVolume(const MqlRates &R[], int centerBar, int period, int total) {
   double sum = 0.0;
   int cnt = 0;
   for(int i = centerBar+1; i < centerBar+1+period && i < total; i++) {
      sum += (double)R[i].tick_volume;
      cnt++;
   }
   return (cnt > 0) ? sum / cnt : 0.0;
}
```

- [ ] **Step 2: Add HasFVG() helper — used for Tertiary confirmation**

```mql5
// Checks if a bullish or bearish FVG exists starting at bar[startBar]
// within the next 3 bars. dir: +1=bullish FVG, -1=bearish FVG
bool HasFVG(const MqlRates &R[], int startBar, int dir, int total) {
   for(int i = startBar; i >= 2 && i > startBar-4; i--) {
      if(dir > 0 && R[i+1].high < R[i-1].low)  return true; // gap up
      if(dir < 0 && R[i+1].low  > R[i-1].high) return true; // gap down
   }
   return false;
}
```

- [ ] **Step 3: Add ScanManipulation() helper**

```mql5
void ScanManipulation(const MqlRates &R[], int copied, AMDRec &rec,
                      datetime dayStart, datetime dayEnd, int gmt_sec) {
   if(rec.accumHi <= rec.accumLo + _Point*2) return;

   // Determine manipulation scan window
   int manipStartH = (InpAMDMode == AMD_SESSION) ? InpAMDLonStart : InpAMDAsiaEnd;
   int manipEndH   = (InpAMDMode == AMD_SESSION) ? InpAMDLonEnd   : 24;

   for(int b = copied-1; b >= 0; b--) {
      datetime bt = R[b].time - gmt_sec;
      if(bt < dayStart || bt >= dayEnd) continue;
      int hr = HourFromTime(bt);
      if(hr < manipStartH || hr >= manipEndH) continue;

      bool sweptHigh = (R[b].high > rec.accumHi && R[b].close < rec.accumHi);
      bool sweptLow  = (R[b].low  < rec.accumLo && R[b].close > rec.accumLo);
      if(!sweptHigh && !sweptLow) continue;

      int dir = sweptHigh ? 1 : -1;

      // Primary confirmation — close back inside range
      int level = 1;
      if(InpAMDConf >= CONF_SECONDARY) {
         // Secondary: volume spike
         double avg = AvgVolume(R, b, InpVolAvgBars, copied);
         if(avg > 0.0 && (double)R[b].tick_volume < avg * InpVolSpikeMin)
            continue; // not enough volume — skip
         level = 2;
      }
      if(InpAMDConf >= CONF_TERTIARY) {
         // Tertiary: FVG in distribution direction within next 3 bars
         int fvgDir = -dir; // distribution is opposite of manipulation
         if(!HasFVG(R, b, fvgDir, copied))
            continue;
         level = 3;
      }

      rec.manipDir      = dir;
      rec.manipExtreme  = sweptHigh ? R[b].high : R[b].low;
      rec.manipTime     = R[b].time;
      rec.confLevel     = level;

      double sweep = MathAbs(rec.manipExtreme - (sweptHigh ? rec.accumHi : rec.accumLo));
      if(dir > 0) // swept highs → dist DOWN
         rec.distTarget = rec.accumLo - sweep;
      else        // swept lows → dist UP
         rec.distTarget = rec.accumHi + sweep;

      break; // take first confirmed manipulation per day
   }
}
```

- [ ] **Step 4: Call ScanManipulation() inside CalcAMD() loop**

Inside CalcAMD(), after `g_amd[g_nAMD++] = rec;` but BEFORE the increment — restructure the loop end:

Replace the last part of the day loop:
```mql5
      if(rec.accumHi == -DBL_MAX || rec.accumHi <= rec.accumLo + _Point*2) {
         rec.accumHi = 0; rec.accumLo = 0;
         g_amd[g_nAMD++] = rec;
         continue;
      }

      ScanManipulation(R, copied, rec, dayStart, dayEnd, gmt_sec);
      g_amd[g_nAMD++] = rec;
```

- [ ] **Step 5: Compile in MetaEditor (F7)**

Expected: `0 errors, 0 warnings`

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(amd): manipulation detection + 3-level confirmation"
```

---

### Task 5: Implement RenderAMD()

**Files:**
- Modify: `VP_MultiTF_Suite.mq5` — add RenderAMD() and MkAMDObj() helper before `OnDeinit`

**Interfaces:**
- Consumes: `g_amd[]`, `g_nAMD`, all `InpAMD*` / `InpAccumClr` / `InpManipClr` / `InpDistClr` inputs
- Produces: chart objects with prefix `g_pfx + "AMD_"`

- [ ] **Step 1: Add MkAMDRect() helper**

Insert before RenderAMD():

```mql5
void MkAMDRect(string id, datetime t1, double p1, datetime t2, double p2,
               color clr, bool filled, bool back) {
   string nm = g_pfx + "AMD_" + id;
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, nm, OBJPROP_FILL,       filled);
   ObjectSetInteger(0, nm, OBJPROP_BACK,       back);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
}

void MkAMDText(string id, datetime t, double p, string txt, color clr, int sz,
               ENUM_ANCHOR_POINT anchor) {
   string nm = g_pfx + "AMD_" + id;
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   ObjectCreate(0, nm, OBJ_TEXT, 0, t, p);
   ObjectSetString (0, nm, OBJPROP_TEXT,       txt);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,   sz);
   ObjectSetString (0, nm, OBJPROP_FONT,       "Consolas");
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR,     anchor);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
}

void MkAMDHLine(string id, double price, color clr) {
   string nm = g_pfx + "AMD_" + id;
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   ObjectCreate(0, nm, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, nm, OBJPROP_STYLE,      STYLE_DOT);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
}
```

- [ ] **Step 2: Add RenderAMD()**

```mql5
void RenderAMD() {
   ObjectsDeleteAll(0, g_pfx + "AMD_");
   if(!InpAMDShow || g_nAMD == 0) return;

   int    psec     = PeriodSeconds(PERIOD_CURRENT);
   datetime lblOff = (datetime)(psec * 2);

   for(int d = 0; d < g_nAMD; d++) {
      AMDRec r = g_amd[d];
      if(r.accumHi <= r.accumLo + _Point*2) continue;

      string ds = TimeToString(r.dateKey, TIME_DATE);

      // ── Accumulation box ──
      if(r.accumStart > 0 && r.accumEnd > r.accumStart) {
         double opacity = (r.confLevel >= 1) ? 1.0 : 0.4;
         color  aclr    = r.confLevel >= 1 ? InpAccumClr
                        : (color)(((int)InpAccumClr >> 1) & 0x7F7F7F);
         MkAMDRect(ds+"_AB", r.accumStart, r.accumHi, r.accumEnd, r.accumLo,
                   aclr, true, true);
         MkAMDText(ds+"_AL", r.accumStart + lblOff, r.accumHi, "ACCUM",
                   clrSilver, InpLblSz, ANCHOR_LEFT_LOWER);
      }

      if(r.manipDir == 0) continue;

      // ── Manipulation candle ──
      if(r.confLevel >= 1 && r.manipTime > 0) {
         datetime m1 = r.manipTime;
         datetime m2 = m1 + (datetime)psec;
         MqlRates MR[];
         ArraySetAsSeries(MR, true);
         if(CopyRates(_Symbol, PERIOD_CURRENT, m1, 1, MR) > 0) {
            MkAMDRect(ds+"_MC", m1, MR[0].high, m2, MR[0].low,
                      InpManipClr, false, false);
         }
         string mlbl = (r.manipDir > 0) ? "MANIP ↓?" : "MANIP ↑?";
         if(r.confLevel >= 2) mlbl = (r.manipDir > 0) ? "MANIP ↓" : "MANIP ↑";
         ENUM_ANCHOR_POINT anch = (r.manipDir > 0) ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER;
         double tp = (r.manipDir > 0) ? r.manipExtreme + g_pip*2 : r.manipExtreme - g_pip*2;
         MkAMDText(ds+"_ML", m1, tp, mlbl, InpManipClr, InpLblSz, anch);
      }

      // ── Distribution target (Secondary+ confirmed) ──
      if(r.confLevel >= 2 && r.distTarget != 0.0) {
         MkAMDHLine(ds+"_DT", r.distTarget, InpDistClr);
         datetime now = iTime(_Symbol, PERIOD_CURRENT, 0);
         string dlbl = (r.manipDir > 0) ? "DIST TARGET ↓" : "DIST TARGET ↑";
         MkAMDText(ds+"_DL", now + lblOff, r.distTarget, dlbl,
                   InpDistClr, InpLblSz, ANCHOR_LEFT_LOWER);
      }
   }
}
```

- [ ] **Step 3: Compile in MetaEditor (F7)**

Expected: `0 errors, 0 warnings`

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(amd): RenderAMD drawing — boxes, manipulation, targets"
```

---

### Task 6: Wire AMD into OnCalculate + OnDeinit, bump version

**Files:**
- Modify: `VP_MultiTF_Suite.mq5` — OnCalculate (~line 127), OnDeinit (~line 122), version line

**Interfaces:**
- Consumes: `CalcAMD()`, `RenderAMD()`, `g_amdDirty` from Tasks 3–5

- [ ] **Step 1: Bump version to 4.00**

Change:
```mql5
#property version   "3.00"
```
To:
```mql5
#property version   "4.00"
```

Also update the comment header:
```mql5
//|    Volume Profile Multi-TF Lines  v4.00                          |
```

- [ ] **Step 2: Add AMD cleanup to OnDeinit**

Change:
```mql5
void OnDeinit(const int reason) { ObjectsDeleteAll(0, g_pfx); }
```
To:
```mql5
void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, g_pfx);
   ObjectsDeleteAll(0, g_pfx + "AMD_");
}
```

- [ ] **Step 3: Wire CalcAMD + RenderAMD into OnCalculate**

After the existing `if(dirty) { ... }` block (after `RenderTable()` call), add:

```mql5
   if(InpAMDShow) {
      CalcAMD();
      if(g_amdDirty) {
         RenderAMD();
         g_amdDirty = false;
      }
   }
```

- [ ] **Step 4: Compile in MetaEditor (F7)**

Expected: `0 errors, 0 warnings`

- [ ] **Step 5: Visual test on chart**

Load indicator on XAUUSD H1 with default settings:
1. Settings → AMD Mode = SESSION, GMT offset = your broker offset
2. Verify: Asia range box appears (semi-transparent)
3. Change mode to SWING → Swing-based range appears
4. Change Confirmation = SECONDARY → ensure manipulation label only shows when volume spike present
5. Confirm no old AMD objects linger after settings change (OnDeinit cleans up)

- [ ] **Step 6: Final commit**

```bash
git add "C:/Users/Pandara Actor/AppData/Roaming/MetaQuotes/Terminal/B9CD1E3322764DD9E8845B7C56122B7D/MQL5/Indicators/VP_MultiTF_Suite.mq5"
git commit -m "feat(amd): wire AMD into pipeline, bump v4.00"
```

---

## Self-Review

**Spec coverage check:**
- ✅ 3 detection modes (SESSION/SWING/MANUAL) — Task 3
- ✅ 3 confirmation levels (PRIMARY/SECONDARY/TERTIARY) — Task 4
- ✅ Accumulation box rendering — Task 5
- ✅ Manipulation candle highlight + label — Task 5
- ✅ Distribution target HLINE + label — Task 5
- ✅ AMD_SWING uses D1>H4>highest active — Task 3 FindSwingTFIdx()
- ✅ Object prefix `g_pfx + "AMD_"` — Task 5
- ✅ OnDeinit cleanup — Task 6
- ✅ Version 4.00 — Task 6
- ✅ g_amdDirty flag prevents flicker — Task 3 + 6

**Placeholder scan:** None found.

**Type consistency:**
- `AMDRec` struct fields used consistently across Tasks 3, 4, 5
- `g_amd[]` / `g_nAMD` / `g_amdDirty` declared Task 1, written Task 3–4, read Task 5–6 ✅
- `MkAMDRect` / `MkAMDText` / `MkAMDHLine` declared Task 5, called Task 5 ✅
- `FindSwingTFIdx()` / `HourFromTime()` / `TruncDay()` declared Task 3, called Task 3 ✅
- `AvgVolume()` / `HasFVG()` / `ScanManipulation()` declared Task 4, called Task 4 ✅
