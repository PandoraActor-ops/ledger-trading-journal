# AMD Feature Design — VP_MultiTF_Suite v4.00

**Date:** 2026-06-18  
**File:** `VP_MultiTF_Suite.mq5`  
**Scope:** Add ICT AMD (Accumulation / Manipulation / Distribution) detection and display  
**Version bump:** 3.00 → 4.00

---

## 1. Summary

Add an AMD layer to the existing Volume Profile indicator. The feature detects the 3-phase ICT Power of 3 model (Accumulation → Manipulation → Distribution) and renders it on chart alongside existing VP lines. All parameters are user-configurable; the feature can be disabled independently of VP.

---

## 2. New Inputs

### AMD Settings group
```mql5
input group "── AMD Settings ──"
input bool      InpAMDShow      = true;         // Enable AMD overlay
enum EAMD_MODE { AMD_SESSION, AMD_SWING, AMD_MANUAL };
input EAMD_MODE InpAMDMode      = AMD_SESSION;  // Accumulation detection mode
input int       InpAMDGMTOff    = 0;            // Broker GMT offset (hours)
input int       InpAMDAsiaStart = 0;            // Asia range start hour (GMT)
input int       InpAMDAsiaEnd   = 8;            // Asia range end hour (GMT)
input int       InpAMDLonStart  = 8;            // Manipulation window start (GMT, SESSION mode)
input int       InpAMDLonEnd    = 13;           // Manipulation window end (GMT, SESSION mode)
input int       InpAMDLookback  = 3;            // Days of AMD history to display
input color     InpAccumClr     = C'40,60,80';  // Accumulation box color
input color     InpManipClr     = clrOrangeRed; // Manipulation highlight color
input color     InpDistClr      = clrLimeGreen; // Distribution target/label color
```

### AMD Confirmation group
```mql5
input group "── AMD Confirmation ──"
enum EAMD_CONF { CONF_PRIMARY, CONF_SECONDARY, CONF_TERTIARY };
input EAMD_CONF InpAMDConf     = CONF_PRIMARY;  // Required confirmation level
input int       InpVolAvgBars  = 20;            // Volume MA period (Secondary+)
input double    InpVolSpikeMin = 1.5;           // Volume spike ratio vs avg (Secondary+)
```

---

## 3. Data Structures

### Enum (new)
```mql5
enum EAMD_MODE { AMD_SESSION, AMD_SWING, AMD_MANUAL };
enum EAMD_CONF { CONF_PRIMARY, CONF_SECONDARY, CONF_TERTIARY };
```

### AMDRec struct (new)
```mql5
struct AMDRec {
   datetime dateKey;       // Day truncated to 00:00
   double   accumHi;       // Accumulation range high
   double   accumLo;       // Accumulation range low
   datetime accumStart;    // Accumulation period start (chart time)
   datetime accumEnd;      // Accumulation period end (chart time)
   int      manipDir;      // +1 swept highs (→ BEAR dist), -1 swept lows (→ BULL dist), 0 = none
   double   manipExtreme;  // Price manipulation reached
   datetime manipTime;     // Bar time of manipulation candle
   double   distTarget;    // Measured move target price
   int      confLevel;     // 0=none, 1=primary, 2=secondary, 3=tertiary
};
```

### Globals (new)
```mql5
AMDRec g_amd[10];
int    g_nAMD = 0;
```

---

## 4. Detection Logic

### CalcAMD()
Called on every new M1 bar (real-time detection) or when `prev_calculated == 0`.

**Step 1 — Build accumulation range per day:**

| Mode | Accumulation source |
|------|-------------------|
| `AMD_SESSION` | Bars within [AsiaStart, AsiaEnd) GMT on each day |
| `AMD_SWING` | `g_tf[idx].hi` / `g_tf[idx].lo` from VP swing — use D1 if active, else highest active TF ≥ H4, else highest available TF |
| `AMD_MANUAL` | Bars within [AsiaStart, AsiaEnd) GMT (user-defined hours) |

**Step 2 — Detect Manipulation:**

Scan bars in the manipulation window (SESSION: [LonStart, LonEnd); SWING/MANUAL: all bars same day after accumulation):

```
Swept highs: bar.high > accumHi AND bar.close < accumHi → manipDir = +1
Swept lows:  bar.low  < accumLo AND bar.close > accumLo → manipDir = -1
Take first confirmed candle per day only.
```

**Step 3 — Confirmation levels:**

```
CONF_PRIMARY (level 1):
  pierce + close_inside_range

CONF_SECONDARY (level 2):
  PRIMARY + tick_volume > avg_volume(InpVolAvgBars) * InpVolSpikeMin

CONF_TERTIARY (level 3):
  SECONDARY + (FVG in next 1-3 bars after reversion
               OR BOS in distribution direction within 5 bars)
```

FVG detection: 3-candle pattern where candle[i-1].high < candle[i+1].low (bullish) or candle[i-1].low > candle[i+1].high (bearish).

**Step 4 — Distribution target:**
```
Bull (manipDir = -1): distTarget = accumHi + (accumLo - manipExtreme)
Bear (manipDir = +1): distTarget = accumLo - (manipExtreme - accumHi)
```

---

## 5. Rendering

**Object prefix:** `g_pfx + "AMD_"` (cleaned up independently in RenderAMD + OnDeinit)

**Per AMDRec, draw:**

| State | Objects drawn |
|-------|--------------|
| No manipulation detected | Accumulation box (faint, BACK=true) + "ACCUM" label |
| Primary confirmed | Box (full opacity) + Manipulation candle rect + "MANIP ↑/↓?" label (orange) |
| Secondary/Tertiary confirmed | All above + Distribution target HLINE + "DIST TARGET" label (InpDistClr) |

**Object details:**

| Object | MQL5 type | Key properties |
|--------|-----------|----------------|
| Accumulation box | `OBJ_RECTANGLE` | [accumStart, accumEnd] × [accumLo, accumHi], BACK=true, FILL=true |
| "ACCUM" label | `OBJ_TEXT` | Top-left corner of box |
| Manipulation rect | `OBJ_RECTANGLE` | [manipTime-halfbar, manipTime+halfbar] × [bar.low, bar.high], BACK=false |
| "MANIP" label | `OBJ_TEXT` | Above/below manipulation candle |
| Distribution target | `OBJ_HLINE` | price=distTarget, STYLE_DOT, color=InpDistClr |
| "DIST TARGET" label | `OBJ_TEXT` | Right side of target line |

Object naming: `g_pfx + "AMD_D" + dateStr + "_" + objectType` (unique per day per type)

---

## 6. Integration into OnCalculate

```
OnCalculate()
  ├── [existing] new-bar check per VP TF → CalcTF() → dirty flag
  ├── [existing] if dirty: BuildLines() → ScoreStrength() → RenderLines() → RenderTable()
  └── [new] if InpAMDShow:
               CalcAMD()   // runs on every tick for real-time manipulation detection
               RenderAMD() // redraws AMD objects if CalcAMD changed any AMDRec
```

CalcAMD tracks a `g_amdDirty` flag — only calls RenderAMD when state actually changes, avoiding flicker.

**OnDeinit addition:**
```mql5
ObjectsDeleteAll(0, g_pfx + "AMD_");
```

---

## 7. Out of Scope

- No AMD dashboard table (VP table already on chart)
- No multi-instrument AMD comparison
- No alert/notification on Manipulation confirmation
- FVG detection is simplified (3-candle gap only, no partial overlap check)

---

## 8. Version

`#property version "4.00"`
