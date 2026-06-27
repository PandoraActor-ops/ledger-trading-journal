# Documentation Index

คู่มือและเอกสารทั้งหมดของ Trading Journal project จัดแยกตามหมวดหมู่

---

## หมวดหมู่

### EA / MT5 Tools
เอกสารเกี่ยวกับ Expert Advisor และเครื่องมือสำหรับ MetaTrader 5

| ไฟล์ | คำอธิบาย |
|------|-----------|
| [TradeAssistantPro_v7_UserManual.md](TradeAssistantPro_v7_UserManual.md) | คู่มือการใช้งาน Trade Assistant Pro v7.0 "Deep Navy" ฉบับสมบูรณ์ |

**ไฟล์ EA (source + compiled):** อยู่ที่ [`tools/mt5/`](../tools/mt5/)
- `LedgerPush.mq5` — EA source สำหรับ push trade data ไป Ledger
- `LedgerPush.ex5` — compiled binary พร้อมใช้งานใน MT5
- `TradingJournalEA_v13.mq5` — EA source สำหรับ Trading Journal v13

---

### Dev Plans & Specs
เอกสารวางแผนและ design spec สำหรับ feature ต่างๆ

| ไฟล์ | คำอธิบาย |
|------|-----------|
| [superpowers/plans/2026-06-18-amd-feature.md](superpowers/plans/2026-06-18-amd-feature.md) | Plan: AMD feature implementation |
| [superpowers/specs/2026-06-18-amd-feature-design.md](superpowers/specs/2026-06-18-amd-feature-design.md) | Design spec: AMD feature |

---

### Skills (Claude Code)
Skills ทั้งหมดอยู่ที่ `.claude/skills/` และ `.agents/skills/`

**Design / UI Skills** (source: `Leonxlnx/taste-skill`)
| Skill | คำอธิบาย |
|-------|-----------|
| `brandkit` | Brand identity และ visual guidelines |
| `design-taste-frontend` | Frontend design taste (latest) |
| `design-taste-frontend-v1` | Frontend design taste (v1) |
| `full-output-enforcement` | บังคับ output ให้ครบถ้วน |
| `gpt-taste` | GPT-style design taste |
| `high-end-visual-design` | High-end visual design guidelines |
| `image-to-code` | แปลง image เป็น code |
| `imagegen-frontend-mobile` | Image gen สำหรับ mobile UI |
| `imagegen-frontend-web` | Image gen สำหรับ web UI |
| `industrial-brutalist-ui` | Industrial/Brutalist UI style |
| `minimalist-ui` | Minimalist UI style |
| `redesign-existing-projects` | Redesign project ที่มีอยู่ |
| `stitch-design-taste` | Stitch design system taste |

---

## โครงสร้างโฟลเดอร์

```
docs/
├── README.md                          ← ไฟล์นี้ (index หลัก)
├── TradeAssistantPro_v7_UserManual.md ← คู่มือ EA
└── superpowers/
    ├── plans/                         ← Implementation plans
    └── specs/                         ← Design specs

tools/
└── mt5/                               ← EA files ทั้งหมด
    ├── LedgerPush.mq5
    ├── LedgerPush.ex5
    └── TradingJournalEA_v13.mq5

screenshots/                           ← Screenshots ทั้งหมด

.claude/skills/                        ← Claude Code skills
.agents/skills/                        ← Agent skills (same set)
skills-lock.json                       ← Skills version lock
```
