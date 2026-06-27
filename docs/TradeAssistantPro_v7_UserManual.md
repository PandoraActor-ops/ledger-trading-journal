# Trade Assistant Pro v7.0 — User Manual

**Version:** 7.0 "Deep Navy"  
**Platform:** MetaTrader 5 (MQL5)  
**File:** `MQL5/Experts/TradeAssistant_Pro_v6_DeepNavy.mq5`

---

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Panel Layout](#panel-layout)
4. [Header & Portfolio Status](#header--portfolio-status)
5. [Tab 1 — Order Entry](#tab-1--order-entry)
6. [Tab 2 — Custom Price](#tab-2--custom-price)
7. [Tab 3 — Pending Orders](#tab-3--pending-orders)
8. [Monitor Position Section](#monitor-position-section)
9. [Slide Panel — Active Checks (ACK)](#slide-panel--active-checks-ack)
10. [Slide Panel — All Trades (TRD)](#slide-panel--all-trades-trd)
11. [Position Zones (Chart Overlay)](#position-zones-chart-overlay)
12. [Draggable SL/TP Lines](#draggable-sltp-lines)
13. [Position P&L Labels](#position-pl-labels)
14. [Input Parameters Reference](#input-parameters-reference)
15. [License & Expiry](#license--expiry)
16. [Tips & Best Practices](#tips--best-practices)

---

## Overview

Trade Assistant Pro v7.0 is a full-featured trade execution panel for MetaTrader 5. It overlays your chart as a compact 296px-wide panel that lets you:

- Execute Market BUY / SELL orders with one click
- Auto-calculate lot size from risk percentage
- Choose from 4 SL and 4 TP calculation modes
- Place all 4 types of pending orders
- Modify live positions with custom SL/TP prices
- Apply Break Even to open positions
- Monitor trailing stops
- Visualize SL/TP zones directly on the chart (TradingView-style shaded bands)
- Drag SL/TP lines on the chart to modify positions in real time
- Monitor all open positions in a slide-out panel

---

## Installation

1. Copy `TradeAssistant_Pro_v6_DeepNavy.mq5` to your MT5 data folder:  
   `%AppData%\MetaQuotes\Terminal\<TERMINAL_ID>\MQL5\Experts\`
2. Open MetaEditor, press **F7** to compile. Verify 0 errors.
3. In MT5, open a chart for your symbol, then drag the EA from the **Navigator** onto the chart.
4. In the EA settings dialog, configure Input Parameters as needed (see [Input Parameters Reference](#input-parameters-reference)).
5. Enable **Algo Trading** (the green button in the MT5 toolbar).

> **Note:** The EA hides MT5's built-in trade level arrows (`CHART_SHOW_TRADE_LEVELS=false`) and draws its own more informative versions.

---

## Panel Layout

```
┌─────────────────────────────────┐
│  TRADE ASSISTANT PRO  v7.0      │  ← Header (title centered)
│  XAUUSD                  12:34  │  ← Symbol + Candle timer (same row)
├─────────────────────────────────┤
│ [-] PORTFOLIO STATUS  [ACK][TRD]│  ← Section collapse + slide panel buttons
│  BALANCE      EQUITY            │
│  OPEN P&L     DAY P&L           │
│  MARGIN LEVEL SPREAD            │
├────────────┬──────────┬─────────┤
│ORDER ENTRY │  CUSTOM  │ PENDING │  ← 3 independent collapse tabs
├────────────┴──────────┴─────────┤
│  [Tab content — depends on open]│
├─────────────────────────────────┤
│ [-] MONITOR POSITION            │  ← Always visible below tabs
│  TRAIL | BREAK EVEN | CLOSE     │
└─────────────────────────────────┘
```

**To the right** (slide panels, hidden by default):
- **[ACK]** → Active Checks panel (risk guards)
- **[TRD]** → All Trades panel (live positions list)

---

## Header & Portfolio Status

### Header Row

| Element | Position | Description |
|---------|----------|-------------|
| Title | Centered top | "TRADE ASSISTANT PRO  v7.0" |
| Symbol | Left, 2nd row | Current chart symbol (e.g., XAUUSD) |
| Candle Timer | Right, 2nd row | Countdown to next candle close |

The candle timer counts down in **MM:SS** format and turns gold when under 10 seconds.

### Portfolio Status Section

Click **`[-] PORTFOLIO STATUS`** to collapse/expand this section.

| Stat Card | Description |
|-----------|-------------|
| **BALANCE** | Account balance in account currency |
| **EQUITY** | Current equity (balance ± floating P&L) |
| **OPEN P&L** | Total floating profit/loss of all open positions |
| **DAY P&L** | Closed trade profit/loss for today |
| **MARGIN LEVEL** | Margin level % (yellow warning below 200%) |
| **SPREAD** | Current bid-ask spread in points |

### [ACK] and [TRD] Buttons

- **[ACK]** — Opens the **Active Checks** slide panel to the right of the main panel. Click again to close.
- **[TRD]** — Opens the **All Trades** slide panel. If ACK is also open, TRD appears further right.

---

## Tab 1 — Order Entry

Click **`ORDER ENTRY`** tab header to expand/collapse.

This is the primary trade execution tab.

### LOT and RISK %

| Field | Description |
|-------|-------------|
| **LOT** | Trade size in lots. Can be typed manually or auto-calculated by AUTOLOT. |
| **RISK %** | Risk percentage of account Balance (or Equity) used for AUTOLOT calculation. |

**How to use:**
- Type your desired lot size directly into the **LOT** field, or
- Enable **AUTOLOT** (see below) and set **RISK %** to let the EA calculate it automatically.

### SL PTS and TP PTS

| Field | Description |
|-------|-------------|
| **SL PTS** | Stop Loss distance in points (used when SL TYPE = Fix) |
| **TP PTS** | Take Profit distance in points (used when TP TYPE = Fix) |

> **Points vs Pips:** For a 5-digit broker (e.g., EURUSD = 1.23456), 1 pip = 10 points. For XAUUSD, 1 point = $0.01.

### SL TYPE — 4 Modes

Click any of the 4 mode buttons to select:

| Button | Mode | How SL is Calculated |
|--------|------|----------------------|
| **Fix** | Fixed points | Entry ± `SL PTS` × point size |
| **Swing** | Swing High/Low | iLowest/iHighest over `InpSwingBars` candles ± `InpSLBuffer` points |
| **Prev** | Previous candle | Previous candle's Low (for BUY) or High (for SELL) ± `InpSLBuffer` points |
| **OB** | Order Block | Nearest ZigZag pivot point ± `InpSLBuffer` points |

**Swing mode example:** If set to 20 bars and current symbol is XAUUSD BUY, SL is placed below the lowest low of the last 20 candles.

**OB mode:** Requires the ZigZag indicator to be configured (see Input Parameters — ZigZag group). The EA reads the most recent ZigZag pivot as the order block boundary.

### TP TYPE — 4 Modes

| Button | Mode | How TP is Calculated |
|--------|------|----------------------|
| **Fix** | Fixed points | Entry ± `TP PTS` × point size |
| **Swing** | Swing High/Low | iHighest/iLowest over `InpSwingBars` candles ± `InpTPBuffer` points |
| **RR** | Risk:Reward | Entry ± (SL distance × `InpRRRatio`) |
| **OB** | Order Block | Nearest opposing ZigZag pivot ± `InpTPBuffer` points |

**RR mode example:** If SL is 150 points and RR Ratio is 2.0, TP is placed at 300 points from entry.

### AUTO SL/TP Toggle

When enabled, the EA automatically applies the selected SL/TP modes to **all existing open positions** every tick. Also draws preview lines on the chart showing where SL/TP would be placed for a new trade.

- **ON** — EA manages SL/TP for all matching positions continuously.
- **OFF** — SL/TP is only set at the moment of order execution.

### AUTOLOT Toggle

When enabled, the LOT field updates automatically in real time based on:

```
Lot = (Account Balance × Risk%) ÷ (SL_pts × Pip_Value_per_lot)
```

- Updates every second (via timer)
- Updates immediately when you change RISK % or SL PTS
- `InpRiskMode = 0` uses Balance; `= 1` uses Equity

**Example:** Balance = $10,000, Risk = 1%, SL = 300 pts, Pip value = $1/pip → Lot = (10000 × 0.01) ÷ (30 × 1) = **0.33 lots**

### BUY / SELL Buttons

The primary trade execution buttons. When clicked:

1. Calculates SL and TP based on current mode
2. Applies lot size (manual or AUTOLOT)
3. Sends an async market order via `OrderSendAsync`
4. Draws position zones on the chart

> **Tip:** Always verify your SL/TP preview lines (shown when AUTO SL/TP is ON) before pressing BUY/SELL.

---

## Tab 2 — Custom Price

Click **`CUSTOM`** tab header to expand/collapse.

Use this tab to **manually apply a specific SL or TP price** to existing open positions.

### SL PRICE and TP PRICE

Type your desired price level directly into the field.

These fields also sync with the **draggable SL/TP lines** on the chart — dragging a line updates the field automatically.

### Apply Buttons

| Button | Action |
|--------|--------|
| **SL→BUY** | Apply the SL PRICE to all BUY positions |
| **SL→SELL** | Apply the SL PRICE to all SELL positions |
| **TP→BUY** | Apply the TP PRICE to all BUY positions |
| **TP→SELL** | Apply the TP PRICE to all SELL positions |

**How to use:**
1. Type the price in the **SL PRICE** or **TP PRICE** field.
2. Click the appropriate apply button.
3. The EA validates against minimum stop level before modifying.

**Or:** Drag the SL/TP dotted line on the chart to the desired level, and the modification is applied instantly.

---

## Tab 3 — Pending Orders

Click **`PENDING`** tab header to expand/collapse.

Use this tab to place pending orders at a calculated distance or at a specific price.

### DIST (PTS)

Distance in points from current price to place the pending order (used for Stop/Limit buttons).

### At Price Field

Type an exact price to place the pending order. Click **[×]** to clear the field.

- If the **At Price** field is filled → order is placed at that exact price.
- If empty → order is placed at current price ± DIST.

### Order Type Buttons

| Button | Order Type | When Triggered |
|--------|-----------|----------------|
| **BUY STOP** | Buy Stop | When ask rises to the order price (above current) |
| **SELL STOP** | Sell Stop | When bid falls to the order price (below current) |
| **BUY LIMIT** | Buy Limit | When ask falls to the order price (below current) |
| **SELL LIMIT** | Sell Limit | When bid rises to the order price (above current) |

**Example — BUY STOP with DIST:**
- Current price: 2350.00
- DIST: 200 pts = 2.00 USD
- Order placed at: 2352.00

**Example — SELL LIMIT at specific price:**
- Fill "At Price" = 2365.50
- Click SELL LIMIT → pending order placed at 2365.50

---

## Monitor Position Section

Click **`[-] MONITOR POSITION`** to collapse/expand.

This section manages existing open positions.

### Trailing Stop

| Control | Description |
|---------|-------------|
| **TRAIL** field | Trailing start distance in points. EA begins trailing only after price moves this far in profit. |
| **TRAIL ON / OFF** | Toggle trailing stop on or off globally. |

**How Trailing Stop works:**
- BUY position: once price moves `InpTrailStart` points above entry, SL is moved to `current price - InpTrailStart`.
- SL only moves forward (never back) and only when the new SL is at least `InpTrailStep` points better than the current SL.

### Break Even

Four Break Even buttons that move SL to entry (or better):

| Button | Action |
|--------|--------|
| **BE Avg BUY** | Move all BUY positions' SL to the volume-weighted average entry price + `InpBE_FixPoints` buffer |
| **BE Avg SELL** | Same for all SELL positions |
| **Fix** | Move each position's SL to its own entry price + `InpBE_FixPoints` |
| **Prev** | Move SL to the previous candle's Low (BUY) or High (SELL) with `InpBE_Buffer` offset |
| **Zig** | Move SL to the nearest ZigZag pivot level with `InpBE_Buffer` offset |

**When to use:**
- Use **BE Avg** when you have multiple BUY or SELL positions at different entries — it averages them.
- Use **Fix** to move each position independently to its own entry.
- Use **Prev** or **Zig** to trail to a structural level rather than exact entry.

### Close Buttons

| Button | Action |
|--------|--------|
| **CLOSE BUY** | Market close all BUY positions and cancel BUY pending orders |
| **CLOSE SELL** | Market close all SELL positions and cancel SELL pending orders |
| **CLOSE ALL** | Market close everything (all positions + all pending orders) |

All close operations use `OrderSendAsync` for fast execution.

---

## Slide Panel — Active Checks (ACK)

Click **[ACK]** in the Portfolio Status header to open/close this panel (appears to the right of main panel).

Active Checks are **risk guards** that block trade execution when limits are breached.

### Three Risk Guards

| Guard | Input | When Blocked |
|-------|-------|-------------|
| **DAILY LOSS** | `InpMaxDailyLoss` (e.g., $200) | Today's closed P&L is worse than -$200 |
| **MAX DD%** | `InpMaxDD_Pct` (e.g., 5%) | Drawdown from Balance exceeds 5% |
| **MAX TRADES** | `InpMaxOpenTrades` (e.g., 10) | Number of open positions ≥ 10 |

Each guard has a toggle (ON/OFF). Disabled guards do not block trades.

### Status Bar

At the bottom of the ACK panel:

- **TRADE OK** (green) — No guards are triggered. BUY/SELL buttons will work.
- **TRADE BLOCKED** (red) — At least one enabled guard is triggered. BUY/SELL are disabled.

**How to use:**
1. Enable the guards you want active via their toggle buttons.
2. Set limits in the Input Parameters (`InpMaxDailyLoss`, `InpMaxDD_Pct`, `InpMaxOpenTrades`).
3. The status updates automatically every second.

---

## Slide Panel — All Trades (TRD)

Click **[TRD]** in the Portfolio Status header to open/close this panel.

Displays a live table of all open positions and pending orders on the current symbol.

### Table Columns

| Column | Description |
|--------|-------------|
| **TYPE** | BUY / SELL |
| **ENTRY** | Entry price (7 decimal places for precision) |
| **P&L** | Floating profit/loss in account currency (includes swap) |

> **Note:** LOT column is omitted because the 148px panel width cannot accommodate XAUUSD's 8-digit prices in 4 columns without overlap. Lot size is visible in the position P&L label on the chart.

The table shows up to 8 rows. Positions are listed newest first. P&L is highlighted green (profit) or red (loss).

---

## Position Zones (Chart Overlay)

TradingView-style shaded zones are drawn on the chart for every open position, showing SL and TP risk areas visually.

### Zone Behavior

| Zone | Color | What It Shows |
|------|-------|---------------|
| **SL zone** (red band) | `InpZoneColorSL` / `InpZoneColorSLActive` | Area between entry and SL price |
| **TP zone** (green band) | `InpZoneColorTP` / `InpZoneColorTPActive` | Area between entry and TP price |

### Dynamic Color Change

- **SL zone becomes bright** (`InpZoneColorSLActive`) when current price has moved to the **losing side** of entry.
- **TP zone becomes bright** (`InpZoneColorTPActive`) when current price has moved to the **winning side** of entry.

This gives instant visual feedback on which direction the trade is pressured.

### Zone Labels

Each zone displays a text label at the SL / TP price level (2 bars to the right of current candle):

- **Stop label** (red text): `Stop: 23.97 $ (0.572%)` — dollar risk and % of entry price
- **Target label** (green text): `Target: 48 $ (1.146%)` — dollar reward and % of entry price

Label colors are set by `InpZoneLblColorSL` and `InpZoneLblColorTP`.

### Customizing Zone Colors

All 6 zone colors are configurable in the Input Parameters under **Zone Colors**:

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `InpZoneColorSL` | Dark red | SL zone — inactive (price not in zone) |
| `InpZoneColorSLActive` | Bright orange-red | SL zone — active (price losing side) |
| `InpZoneColorTP` | Dark green | TP zone — inactive |
| `InpZoneColorTPActive` | Bright green | TP zone — active (price winning side) |
| `InpZoneLblColorSL` | Light red | Stop label text color |
| `InpZoneLblColorTP` | Light green | Target label text color |

---

## Draggable SL/TP Lines

The EA draws dotted horizontal lines on the chart for each position's entry, SL, and TP.

| Line Style | Meaning | Draggable? |
|------------|---------|------------|
| Blue dotted | Entry price | No |
| Red dotted | Stop Loss | **Yes** |
| Green dotted | Take Profit | **Yes** |
| Purple dotted | Pending order entry | Yes (pending only) |

### How to Drag

1. Click on the SL or TP line to select it (a small arrow appears on the line).
2. Drag it to the desired price level.
3. Release — the EA immediately calls `trade.PositionModify()` to update the position's SL/TP.
4. The **SL PRICE** / **TP PRICE** fields in the Custom tab sync automatically.

> **Limitation:** You cannot drag the SL/TP closer than the broker's minimum stop level. The EA silently ignores invalid positions.

---

## Position P&L Labels

A text label appears on the chart at each position's **entry price level**, showing:

```
BUY  0.10 lot   +23.45
SELL 0.05 lot   -8.20
```

- **Green text** = profit
- **Red text** = loss
- Label position: 3 bars to the right of the current candle (auto-scrolls as new candles form)
- Automatically removed when the position is closed

---

## Input Parameters Reference

### General

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DefaultLotSize` | 0.01 | Starting lot size when EA loads |
| `InpMagicNum` | 123456 | Magic number to tag EA's orders |
| `InpPendingDist` | 200 | Default pending order distance in points |

### Risk & Trail

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpUseAutoLot` | false | Enable AUTOLOT on startup |
| `InpRiskPercent` | 1.0 | Risk % for AUTOLOT calculation |
| `InpRiskMode` | 0 | 0 = use Balance; 1 = use Equity |
| `InpUseTrailing` | false | Enable trailing stop on startup |
| `InpTrailStart` | 150 | Trailing start distance (points) |
| `InpTrailStep` | 50 | Minimum SL improvement per trail step (points) |

### SL/TP

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpSLPoints` | 300 | Default SL distance in Fix mode (points) |
| `InpSwingBars` | 20 | Lookback bars for Swing SL/TP mode |
| `InpSLBuffer` | 50 | Buffer added beyond swing/OB level for SL (points) |
| `InpTPPoints` | 600 | Default TP distance in Fix mode (points) |
| `InpRRRatio` | 2.0 | Risk:Reward ratio for RR mode |
| `InpTPBuffer` | 50 | Buffer for TP placement in Swing/OB mode (points) |

### Break Even

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpBE_FixPoints` | 10 | Points above/below entry for Fix BE |
| `InpBE_Buffer` | 20 | Buffer for Prev/Zig BE beyond candle high/low |

### ZigZag (for OB SL/TP and Zig BE)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpZigZagName` | `Examples\ZigZag` | Indicator path (relative to MQL5/Indicators/) |
| `InpZigZagBuf` | 0 | Buffer index of the ZigZag values |
| `InpZigZagDepth` | 12 | ZigZag Depth parameter |
| `InpZigZagDev` | 5 | ZigZag Deviation parameter |
| `InpZigZagBack` | 3 | ZigZag Backstep parameter |

### Async

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpAsyncDeviation` | 50 | Max price deviation for async orders (points) |

### Risk Matrix Lot Presets

Six lot size presets displayed in a 2×3 grid in the Order Entry tab for quick selection.

| Parameter | Default |
|-----------|---------|
| `InpMatLot1` | 0.01 |
| `InpMatLot2` | 0.05 |
| `InpMatLot3` | 0.10 |
| `InpMatLot4` | 0.25 |
| `InpMatLot5` | 0.50 |
| `InpMatLot6` | 1.00 |

Click any preset cell to instantly set the LOT field to that value.

### Active Checks

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpChkDailyLoss` | false | Enable Daily Loss guard on startup |
| `InpMaxDailyLoss` | 200.0 | Maximum daily loss in account currency |
| `InpChkMaxDD` | false | Enable Max Drawdown % guard on startup |
| `InpMaxDD_Pct` | 5.0 | Maximum drawdown % from balance |
| `InpChkMaxTrades` | false | Enable Max Open Trades guard on startup |
| `InpMaxOpenTrades` | 10 | Maximum number of simultaneous open positions |

### Zone Colors

| Parameter | Default (RGB) | Description |
|-----------|---------------|-------------|
| `InpZoneColorSL` | 100,25,25 | SL zone fill — inactive state |
| `InpZoneColorSLActive` | 220,60,30 | SL zone fill — price on losing side |
| `InpZoneColorTP` | 15,70,25 | TP zone fill — inactive state |
| `InpZoneColorTPActive` | 40,180,60 | TP zone fill — price on winning side |
| `InpZoneLblColorSL` | 255,130,130 | Stop label text color |
| `InpZoneLblColorTP` | 100,230,100 | Target label text color |

---

## License & Expiry

### License Parameter

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpExpireDate` | 2026.12.31 23:59 | EA stops loading after this date/time |

When the EA loads:
- If `TimeCurrent()` > `InpExpireDate` → EA refuses to start, shows an **Alert** dialog, and returns `INIT_FAILED`.
- The expiry check uses **server time** (broker time), not local machine time.

### How to Set a Custom Expiry

In the EA properties dialog, change `InpExpireDate` to your desired expiry in the format:  
`YYYY.MM.DD HH:MM`

**Example:** `2027.03.31 23:59` = expires end of March 2027.

---

## Tips & Best Practices

### For Scalping / High-Frequency Symbols
- Use **Fix** SL/TP mode with tight values.
- Keep AUTOLOT ON with 0.5–1% risk to avoid oversizing in fast markets.
- Enable **DAILY LOSS** guard in ACK panel to protect against loss spirals.

### For Swing Trading
- Use **Swing** or **Prev candle** SL mode for structurally-valid stops.
- Use **RR** TP mode with ratio ≥ 2.0 for a positive expectancy.
- Enable **Trailing Stop** once price moves 150+ pts in your favour.

### For Scalping with Multiple Positions
- Open **[TRD]** panel to monitor all positions at a glance.
- Use **CLOSE ALL** button if you need fast exit in volatile conditions.
- Use **BE Avg** Break Even to protect the average entry when scaling in.

### Reading Position Zones
- **SL zone turns bright orange-red** → price is currently in the losing zone. Consider:
  - Break Even application
  - Trailing stop activation
  - Manual review
- **TP zone turns bright green** → price is heading toward your target. Let it run.

### ZigZag-Based Modes (OB SL/TP and Zig BE)
- Ensure the ZigZag indicator is accessible at the path set in `InpZigZagName`.
- The default `Examples\ZigZag` is included with MT5. Custom ZigZags must expose their pivot buffer at `InpZigZagBuf`.
- Use `InpZigZagDepth = 12` for M15 and higher; decrease to 8 for M1/M5.

### Order Execution Notes
- All orders use `OrderSendAsync` for non-blocking execution.
- Requote-protection is handled via `InpAsyncDeviation` (default 50 points).
- Orders are tagged with `InpMagicNum` so they don't conflict with other EAs.

---

*Trade Assistant Pro v7.0 — © 2026. Unauthorized redistribution prohibited.*
