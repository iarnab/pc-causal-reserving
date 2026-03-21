const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, HeadingLevel, BorderStyle, WidthType,
  ShadingType, PageNumber, PageBreak, LevelFormat, ExternalHyperlink
} = require("docx");
const fs = require("fs");

// ── Colours ────────────────────────────────────────────────────────────────
const CAS_BLUE   = "003087";
const LIGHT_BLUE = "D5E8F0";
const MID_BLUE   = "B8D4E8";
const WHITE      = "FFFFFF";
const LIGHT_GREY = "F5F5F5";
const TEXT_GREY  = "444444";

// ── Helpers ────────────────────────────────────────────────────────────────
const border = (color = "CCCCCC") => ({ style: BorderStyle.SINGLE, size: 1, color });
const cellBorders = (color = "CCCCCC") => ({
  top: border(color), bottom: border(color),
  left: border(color), right: border(color)
});
const noBorders = {
  top:    { style: BorderStyle.NONE, size: 0, color: "FFFFFF" },
  bottom: { style: BorderStyle.NONE, size: 0, color: "FFFFFF" },
  left:   { style: BorderStyle.NONE, size: 0, color: "FFFFFF" },
  right:  { style: BorderStyle.NONE, size: 0, color: "FFFFFF" },
};

const hCell = (text, widthDxa, bold = true) => new TableCell({
  borders: cellBorders(CAS_BLUE),
  width: { size: widthDxa, type: WidthType.DXA },
  shading: { fill: CAS_BLUE, type: ShadingType.CLEAR },
  margins: { top: 80, bottom: 80, left: 120, right: 120 },
  children: [new Paragraph({
    children: [new TextRun({ text, bold, color: WHITE, font: "Arial", size: 18 })]
  })]
});

const dCell = (text, widthDxa, shade = false) => new TableCell({
  borders: cellBorders("CCCCCC"),
  width: { size: widthDxa, type: WidthType.DXA },
  shading: shade ? { fill: LIGHT_GREY, type: ShadingType.CLEAR }
                 : { fill: WHITE,      type: ShadingType.CLEAR },
  margins: { top: 80, bottom: 80, left: 120, right: 120 },
  children: [new Paragraph({
    children: [new TextRun({ text, font: "Arial", size: 18, color: TEXT_GREY })]
  })]
});

const spacer = (pts = 100) => new Paragraph({
  spacing: { before: 0, after: pts },
  children: []
});

const body = (text, opts = {}) => new Paragraph({
  spacing: { before: 60, after: 120, line: 276 },
  children: [new TextRun({ text, font: "Arial", size: 20, color: TEXT_GREY, ...opts })]
});

const bodyBullet = (text) => new Paragraph({
  numbering: { reference: "bullets", level: 0 },
  spacing: { before: 40, after: 80 },
  children: [new TextRun({ text, font: "Arial", size: 20, color: TEXT_GREY })]
});

const sectionTitle = (num, text) => new Paragraph({
  heading: HeadingLevel.HEADING_1,
  spacing: { before: 320, after: 160 },
  children: [new TextRun({
    text: `${num}. ${text}`.toUpperCase(),
    bold: true, font: "Arial", size: 24, color: CAS_BLUE
  })]
});

const subTitle = (num, text) => new Paragraph({
  heading: HeadingLevel.HEADING_2,
  spacing: { before: 200, after: 100 },
  children: [new TextRun({ text: `${num}  ${text}`, bold: true, font: "Arial", size: 22, color: CAS_BLUE })]
});

// ── Budget tables ──────────────────────────────────────────────────────────
// Content width for US Letter with 1" margins = 9360 DXA
const CONTENT_W = 9360;
// Phase 1 budget table columns: Role | Detail | Hours | Rate | Amount
const p1Cols = [1600, 3500, 700, 1000, 1200]; // sum = 8000... let me adjust
// Actually let me compute: 9360 total
// Role:1400 | Detail:3500 | Hours:700 | Rate:1100 | Amount:1300 => 8000 no
// Let me use: 1600+3560+700+1000+1500 = 8360... let me just use full width
const col5 = [1700, 3460, 600, 1100, 1500]; // sum = 8360 -- not right
// Just do proportional: 1800+3600+600+1100+1260 = 8360...

// Use 9360 total:
const B1_COLS = [1700, 3800, 600, 1000, 1260]; // sum=8360? 1700+3800=5500+600=6100+1000=7100+1260=8360
// Let me be precise:
// 9360: role=1800, detail=3760, hours=600, rate=1000, amount=1200 => sum=8360
// I'll use: [1800, 3960, 600, 1000, 1000] = 8360
// Actually just: [1500, 4160, 600, 1100, 2000] = 9360
const BUD_COLS = [1500, 4160, 600, 1100, 2000]; // = 9360? 1500+4160=5660+600=6260+1100=7360+2000=9360 YES

function budgetTable1() {
  const rows = [
    new TableRow({ tableHeader: true, children: [
      hCell("Role", BUD_COLS[0]),
      hCell("Detail", BUD_COLS[1]),
      hCell("Hours", BUD_COLS[2]),
      hCell("Rate", BUD_COLS[3]),
      hCell("Amount", BUD_COLS[4])
    ]}),
    new TableRow({ children: [
      dCell("NL Lead Researcher", BUD_COLS[0]),
      dCell("DAG design, CCD framework, evaluation", BUD_COLS[1]),
      dCell("100", BUD_COLS[2]),
      dCell("EUR 225/hr", BUD_COLS[3]),
      dCell("EUR 22,500", BUD_COLS[4])
    ]}),
    new TableRow({ children: [
      dCell("NL Technical Co-Investigator", BUD_COLS[0], true),
      dCell("R implementation, GitHub, RLHF interface", BUD_COLS[1], true),
      dCell("85", BUD_COLS[2], true),
      dCell("EUR 170/hr", BUD_COLS[3], true),
      dCell("EUR 14,500", BUD_COLS[4], true)
    ]}),
    new TableRow({ children: [
      new TableCell({
        columnSpan: 2,
        borders: cellBorders(CAS_BLUE),
        width: { size: BUD_COLS[0] + BUD_COLS[1], type: WidthType.DXA },
        shading: { fill: MID_BLUE, type: ShadingType.CLEAR },
        margins: { top: 80, bottom: 80, left: 120, right: 120 },
        children: [new Paragraph({ children: [new TextRun({ text: "TOTAL Phase 1 — CAS Grant", bold: true, font: "Arial", size: 18, color: CAS_BLUE })] })]
      }),
      dCell("185", BUD_COLS[2], false),
      dCell("EUR 200/hr avg", BUD_COLS[3], false),
      new TableCell({
        borders: cellBorders(CAS_BLUE),
        width: { size: BUD_COLS[4], type: WidthType.DXA },
        shading: { fill: MID_BLUE, type: ShadingType.CLEAR },
        margins: { top: 80, bottom: 80, left: 120, right: 120 },
        children: [new Paragraph({ children: [new TextRun({ text: "EUR 37,000", bold: true, font: "Arial", size: 18, color: CAS_BLUE })] })]
      })
    ]})
  ];
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA },
    columnWidths: BUD_COLS,
    rows
  });
}

// Phase 2 budget: Category | Detail | Amount — 3 cols
const B2_COLS = [2200, 5260, 1900]; // sum = 9360
function budgetTable2() {
  const items = [
    ["Additional NL Research Hours", "75 hrs @ EUR 180/hr — extended DAG modelling, larger actuary panel", "EUR 13,500"],
    ["US Co-Investigator", "50 hrs @ EUR 200/hr — domain review, co-authorship, CAS evaluator coordination", "EUR 10,000"],
    ["Infrastructure & Claude API", "Claude API ~$2,200 + cloud compute ~$1,500 + software licences ~$800", "EUR 4,500"],
    ["Actuary Evaluation Panel", "3 additional FCAS evaluators × 8 hrs @ EUR 150/hr", "EUR 3,600"],
    ["Dissemination (CAS Meeting)", "Travel, accommodation, per diem, registration", "EUR 3,500"],
    ["US/NL Coordination", "Project coordination, milestone reporting, joint work sessions", "EUR 1,900"],
  ];
  const dataRows = items.map((r, i) => new TableRow({ children: [
    dCell(r[0], B2_COLS[0], i % 2 === 0),
    dCell(r[1], B2_COLS[1], i % 2 === 0),
    dCell(r[2], B2_COLS[2], i % 2 === 0)
  ]}));
  const totalRow = new TableRow({ children: [
    new TableCell({
      columnSpan: 2,
      borders: cellBorders(CAS_BLUE),
      width: { size: B2_COLS[0] + B2_COLS[1], type: WidthType.DXA },
      shading: { fill: MID_BLUE, type: ShadingType.CLEAR },
      margins: { top: 80, bottom: 80, left: 120, right: 120 },
      children: [new Paragraph({ children: [new TextRun({ text: "TOTAL Phase 2 — Firm Match", bold: true, font: "Arial", size: 18, color: CAS_BLUE })] })]
    }),
    new TableCell({
      borders: cellBorders(CAS_BLUE),
      width: { size: B2_COLS[2], type: WidthType.DXA },
      shading: { fill: MID_BLUE, type: ShadingType.CLEAR },
      margins: { top: 80, bottom: 80, left: 120, right: 120 },
      children: [new Paragraph({ children: [new TextRun({ text: "EUR 37,000", bold: true, font: "Arial", size: 18, color: CAS_BLUE })] })]
    })
  ]});
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA },
    columnWidths: B2_COLS,
    rows: [
      new TableRow({ tableHeader: true, children: [
        hCell("Category", B2_COLS[0]),
        hCell("Detail", B2_COLS[1]),
        hCell("Amount (EUR)", B2_COLS[2])
      ]}),
      ...dataRows,
      totalRow
    ]
  });
}

// ── Timeline table ─────────────────────────────────────────────────────────
// Period | Focus | Key Deliverables | Milestone — 4 cols
const TL_COLS = [1600, 2100, 4060, 1600]; // sum = 9360
function timelineTable() {
  const rows = [
    ["April 2026\nWks 1–4", "Data Foundation & DAG v1", "Schedule P SQLite schema, triangle construction pipeline, Causal DAG v1 (dagitty spec), external macro data merge", "Data + DAG complete"],
    ["May 2026\nWks 5–8", "Anomaly Engine & Baseline", "ATA Z-score detector, diagonal effects classification, CCD generator v1, baseline LLM evaluation run", "Baseline established"],
    ["June 2026\nWks 9–13", "Adapted System & Eval Round 1", "Counterfactual query framework, CCD+LLM adapted system, evaluation round 1 vs. baseline, interim report", "Interim report 26 Jul"],
    ["July 2026\nWks 14–17", "RLHF & Analysis", "RLHF Shiny review interface, actuary evaluation rounds (2×), prompt refinement, preference dataset compiled", "Actuary ratings complete"],
    ["August 2026\nWks 18–22", "Paper & Delivery", "Research paper, GitHub repo (MPL 2.0), executive summary (1–2 pp), final submission by 31 August", "All deliverables 31 Aug"],
  ];
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA },
    columnWidths: TL_COLS,
    rows: [
      new TableRow({ tableHeader: true, children: [
        hCell("Period", TL_COLS[0]),
        hCell("Focus Area", TL_COLS[1]),
        hCell("Key Deliverables", TL_COLS[2]),
        hCell("Milestone", TL_COLS[3])
      ]}),
      ...rows.map((r, i) => new TableRow({ children: r.map((cell, j) => dCell(cell, TL_COLS[j], i % 2 === 0)) }))
    ]
  });
}

// ── Evaluation table ───────────────────────────────────────────────────────
const EV_COLS = [1800, 7560]; // sum = 9360
function evalTable() {
  const items = [
    ["Causal Attribution Accuracy", "LLM-identified drivers vs. documented historical events (1990-91 recession, tort reform, medical CPI spike). Rubric: 2pts primary driver, 1pt secondary, 0 incorrect. Max 10 per scenario."],
    ["Narrative Quality (Actuary-Rated)", "4–6 FCAS-credentialed reserve actuaries. Four sub-dimensions: accuracy, causal coherence, regulatory tone, completeness. 1–5 Likert scale, blind paired evaluation (baseline vs. adapted)."],
    ["Counterfactual Plausibility", "Actuary panel rating of do-calculus intervention responses. Cross-validated against hindsight Schedule P data (1988–1997 full development = objective ground truth)."],
    ["Output Consistency", "Shannon entropy of key output variables across 10 repeated API calls (temperature=0). Ensures stability required for actuarial reliance."],
  ];
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA },
    columnWidths: EV_COLS,
    rows: [
      new TableRow({ tableHeader: true, children: [
        hCell("Dimension", EV_COLS[0]),
        hCell("Description & Measurement", EV_COLS[1])
      ]}),
      ...items.map((r, i) => new TableRow({ children: [
        dCell(r[0], EV_COLS[0], i % 2 === 0),
        dCell(r[1], EV_COLS[1], i % 2 === 0)
      ]}))
    ]
  });
}

// ── DAG layers table ───────────────────────────────────────────────────────
const DAG_COLS = [1200, 2400, 5760]; // sum = 9360
function dagTable() {
  const layers = [
    ["Layer 1", "Exogenous Shocks", "gdp_growth → payroll_growth; unemployment_rate → claim_frequency; tort_reform → alae_ratio; medical_cpi → avg_case_value"],
    ["Layer 2", "Exposure & Mix Shifts", "payroll_growth → earned_premium; payroll_growth → reported_claims; demographic_shift → avg_case_value"],
    ["Layer 3", "Claim Frequency & Severity", "claim_frequency → reported_claims; reported_claims → case_reserve_opening; avg_case_value → case_reserve_opening; alae_ratio → ibnr_emergence"],
    ["Layer 4", "Case Reserve Adequacy", "case_reserve_opening → development_factor; case_reserve_opening → ibnr_emergence; ibnr_emergence → ultimate_loss"],
    ["Layer 5", "Development Factors & Ultimates", "development_factor → ultimate_loss; tail_factor → ultimate_loss; ultimate_loss → loss_ratio"],
  ];
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA },
    columnWidths: DAG_COLS,
    rows: [
      new TableRow({ tableHeader: true, children: [
        hCell("Layer", DAG_COLS[0]),
        hCell("Name", DAG_COLS[1]),
        hCell("Key Causal Edges", DAG_COLS[2])
      ]}),
      ...layers.map((r, i) => new TableRow({ children: r.map((cell, j) => dCell(cell, DAG_COLS[j], i % 2 === 0)) }))
    ]
  });
}

// ── Document ───────────────────────────────────────────────────────────────
const doc = new Document({
  numbering: {
    config: [{
      reference: "bullets",
      levels: [{ level: 0, format: LevelFormat.BULLET, text: "\u2022",
        alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }]
    }]
  },
  styles: {
    default: {
      document: { run: { font: "Arial", size: 20, color: TEXT_GREY } }
    },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 24, bold: true, font: "Arial", color: CAS_BLUE },
        paragraph: { spacing: { before: 320, after: 160 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 22, bold: true, font: "Arial", color: CAS_BLUE },
        paragraph: { spacing: { before: 200, after: 100 }, outlineLevel: 1 } },
    ]
  },
  sections: [{
    properties: {
      page: {
        size: { width: 12240, height: 15840 },
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 }
      }
    },
    headers: {
      default: new Header({ children: [
        new Paragraph({
          border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: CAS_BLUE, space: 1 } },
          children: [
            new TextRun({ text: "CONFIDENTIAL \u2014 CAS 2026 RFP Submission", font: "Arial", size: 16, color: "888888" }),
            new TextRun({ text: "  |  Page ", font: "Arial", size: 16, color: "888888" }),
            new TextRun({ children: [PageNumber.CURRENT], font: "Arial", size: 16, color: "888888" }),
          ]
        })
      ]})
    },
    footers: {
      default: new Footer({ children: [
        new Paragraph({
          border: { top: { style: BorderStyle.SINGLE, size: 6, color: CAS_BLUE, space: 1 } },
          children: [
            new TextRun({ text: "Submitted March 27, 2026  |  Contact: Arnab Gupta  |  github.com/iarnab/pc-causal-reserving  |  License: MPL 2.0", font: "Arial", size: 16, color: "888888" })
          ]
        })
      ]})
    },
    children: [
      // ── COVER PAGE ──────────────────────────────────────────────────────
      new Paragraph({ spacing: { before: 2400, after: 200 },
        children: [new TextRun({ text: "Causal Intelligence for P&C Loss Reserving", font: "Arial", size: 52, bold: true, color: CAS_BLUE })] }),

      new Paragraph({ spacing: { before: 0, after: 300 },
        children: [new TextRun({ text: "Grounding LLM Reserve Narratives in Explicit Causal Structure", font: "Arial", size: 28, color: "555555" })] }),

      new Paragraph({ spacing: { before: 0, after: 100 },
        border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: CAS_BLUE, space: 1 } },
        children: [] }),
      spacer(200),

      new Paragraph({ spacing: { before: 0, after: 80 },
        children: [new TextRun({ text: "CAS 2026 RFP \u2014 Adapting Large Language Models for Specialized P&C Actuarial Reasoning", font: "Arial", size: 22, color: "555555" })] }),

      spacer(300),

      // Cover table
      new Table({
        width: { size: CONTENT_W, type: WidthType.DXA },
        columnWidths: [2400, 6960],
        rows: [
          new TableRow({ children: [
            new TableCell({ borders: noBorders, width: { size: 2400, type: WidthType.DXA },
              shading: { fill: LIGHT_BLUE, type: ShadingType.CLEAR },
              margins: { top: 100, bottom: 100, left: 140, right: 140 },
              children: [new Paragraph({ children: [new TextRun({ text: "Principal Investigator", font: "Arial", size: 18, bold: true, color: CAS_BLUE })] })] }),
            new TableCell({ borders: noBorders, width: { size: 6960, type: WidthType.DXA },
              margins: { top: 100, bottom: 100, left: 140, right: 140 },
              children: [new Paragraph({ children: [new TextRun({ text: "Arnab Gupta (US)", font: "Arial", size: 20 })] })] }),
          ]}),
          new TableRow({ children: [
            new TableCell({ borders: noBorders, width: { size: 2400, type: WidthType.DXA },
              margins: { top: 100, bottom: 100, left: 140, right: 140 },
              children: [new Paragraph({ children: [new TextRun({ text: "Co-Investigators", font: "Arial", size: 18, bold: true, color: CAS_BLUE })] })] }),
            new TableCell({ borders: noBorders, width: { size: 6960, type: WidthType.DXA },
              shading: { fill: LIGHT_GREY, type: ShadingType.CLEAR },
              margins: { top: 100, bottom: 100, left: 140, right: 140 },
              children: [new Paragraph({ children: [new TextRun({ text: "NL Research Team (Joint US \u00B7 NL Initiative)", font: "Arial", size: 20 })] })] }),
          ]}),
          new TableRow({ children: [
            new TableCell({ borders: noBorders, width: { size: 2400, type: WidthType.DXA },
              shading: { fill: LIGHT_BLUE, type: ShadingType.CLEAR },
              margins: { top: 100, bottom: 100, left: 140, right: 140 },
              children: [new Paragraph({ children: [new TextRun({ text: "Line of Business", font: "Arial", size: 18, bold: true, color: CAS_BLUE })] })] }),
            new TableCell({ borders: noBorders, width: { size: 6960, type: WidthType.DXA },
              shading: { fill: LIGHT_BLUE, type: ShadingType.CLEAR },
              margins: { top: 100, bottom: 100, left: 140, right: 140 },
              children: [new Paragraph({ children: [new TextRun({ text: "Workers Compensation / CAS Schedule P (1988\u20131997)", font: "Arial", size: 20 })] })] }),
          ]}),
          new TableRow({ children: [
            new TableCell({ borders: noBorders, width: { size: 2400, type: WidthType.DXA },
              margins: { top: 100, bottom: 100, left: 140, right: 140 },
              children: [new Paragraph({ children: [new TextRun({ text: "Submission Date", font: "Arial", size: 18, bold: true, color: CAS_BLUE })] })] }),
            new TableCell({ borders: noBorders, width: { size: 6960, type: WidthType.DXA },
              shading: { fill: LIGHT_GREY, type: ShadingType.CLEAR },
              margins: { top: 100, bottom: 100, left: 140, right: 140 },
              children: [new Paragraph({ children: [new TextRun({ text: "March 27, 2026", font: "Arial", size: 20 })] })] }),
          ]}),
          new TableRow({ children: [
            new TableCell({ borders: noBorders, width: { size: 2400, type: WidthType.DXA },
              shading: { fill: LIGHT_BLUE, type: ShadingType.CLEAR },
              margins: { top: 100, bottom: 100, left: 140, right: 140 },
              children: [new Paragraph({ children: [new TextRun({ text: "GitHub Repository", font: "Arial", size: 18, bold: true, color: CAS_BLUE })] })] }),
            new TableCell({ borders: noBorders, width: { size: 6960, type: WidthType.DXA },
              shading: { fill: LIGHT_BLUE, type: ShadingType.CLEAR },
              margins: { top: 100, bottom: 100, left: 140, right: 140 },
              children: [new Paragraph({ children: [new ExternalHyperlink({ link: "https://github.com/iarnab/pc-causal-reserving",
                children: [new TextRun({ text: "github.com/iarnab/pc-causal-reserving", font: "Arial", size: 20, style: "Hyperlink" })] })] })] }),
          ]}),
          new TableRow({ children: [
            new TableCell({ borders: noBorders, width: { size: 2400, type: WidthType.DXA },
              margins: { top: 100, bottom: 100, left: 140, right: 140 },
              children: [new Paragraph({ children: [new TextRun({ text: "Total Budget", font: "Arial", size: 18, bold: true, color: CAS_BLUE })] })] }),
            new TableCell({ borders: noBorders, width: { size: 6960, type: WidthType.DXA },
              shading: { fill: LIGHT_GREY, type: ShadingType.CLEAR },
              margins: { top: 100, bottom: 100, left: 140, right: 140 },
              children: [new Paragraph({ children: [new TextRun({ text: "EUR 37,000 CAS Grant (~$40K USD) + EUR 37,000 Firm Match (~$40K USD) = ~$80,000 USD Total", font: "Arial", size: 20 })] })] }),
          ]}),
        ]
      }),

      new Paragraph({ children: [new PageBreak()] }),

      // ── SECTION 1: ABSTRACT ─────────────────────────────────────────────
      sectionTitle("1", "Abstract"),
      body("Current large language models used in P&C loss reserving lack causal awareness \u2014 they describe development patterns but cannot distinguish a structural break from tort reform versus claims inflation, cannot produce auditable causal attributions, and cannot reason counterfactually about reserve drivers. This research addresses the interpretability gap by building a five-module R pipeline that grounds every LLM reserve narrative in an explicit 5-layer causal Directed Acyclic Graph (DAG) of the loss development process."),
      body("The core innovation is the Causal Context Document (CCD): a SHA-256-registered XML document injected into every Claude API prompt, encoding the active causal subgraph, anomaly context, evidence node values, and do-calculus intervention queries derived from the causal DAG. This structured context engineering approach moves LLM narrative generation from pattern description to causal attribution \u2014 meeting the CAS RFP\u2019s requirement for meaningful adaptation rather than generic LLM application."),
      body("The system is evaluated on CAS Schedule P Workers Compensation data (1988\u20131997) using four dimensions: causal attribution accuracy against documented historical events (1990\u201391 recession, tort reform), narrative quality rated by 4\u20136 FCAS-credentialed actuaries on a Likert scale, counterfactual plausibility cross-validated against hindsight development data, and output consistency via Shannon entropy across repeated runs. An RLHF feedback loop generates preference data for prompt refinement. All code is released open-source under MPL 2.0 via GitHub. The research is directly reproducible by any technically proficient actuary."),

      // ── SECTION 2: PROBLEM ─────────────────────────────────────────────
      sectionTitle("2", "Problem Statement"),
      subTitle("2.1", "The Interpretability Gap in Current LLM Reserving Applications"),
      body("Chain-ladder and Bornhuetter-Ferguson methods have served the actuarial profession for decades, but they capture historical development patterns \u2014 not the causal mechanisms behind them. When development deviates from expectation, actuaries must manually triangulate across macroeconomic data, claims operations records, and institutional memory to explain the deviation. This is precisely the analytical task where LLMs are currently being deployed."),
      body("However, current LLM usage in reserving has a critical limitation: these models treat loss triangles as tabular text with no causal awareness. A general-purpose LLM can describe that AY 1993 Workers Compensation development factors were elevated, but it cannot determine whether this elevation was caused by medical cost inflation, case reserve under-adequacy, a tort environment change, or a diagonal effect from claims operations. It describes patterns but cannot reason causally."),
      body("This creates an auditability problem. Actuarial opinions require traceable, reproducible reasoning. A narrative generated by an LLM operating on raw triangle data \u2014 with no explicit causal model \u2014 is neither traceable to specific causal drivers nor reproducible across runs."),
      subTitle("2.2", "Why Generic LLM Adaptation Is Insufficient"),
      body("The CAS RFP explicitly distinguishes meaningful LLM adaptation from generic application. The interpretability gap is not solved by fine-tuning (insufficient actuarial training data, low interpretability of tuned weights) or by vector-similarity RAG (which retrieves text by semantic similarity, not causal relevance). The gap requires a structural solution: pre-conditioning the LLM context with the output of a causal analysis, so that narrative generation operates on causally pre-processed inputs rather than raw triangles."),

      // ── SECTION 3: APPROACH ─────────────────────────────────────────────
      sectionTitle("3", "Proposed Approach \u2014 The CCD Architecture"),
      subTitle("3.1", "Structured Context Engineering"),
      body("The primary adaptation technique is structured context engineering via the Causal Context Document (CCD). The CCD is generated deterministically from the causal DAG and anomaly detection outputs, and is injected as the structured context in every LLM API call. This is not generic RAG \u2014 the CCD is not retrieved by vector similarity but is constructed deterministically from the causal analysis pipeline, transforming the LLM prompt from:"),
      body("\u201cHere is the raw loss triangle. Describe the development pattern.\u201d", { italics: true }),
      body("to:"),
      body("\u201cHere is the causal subgraph activated by the detected anomaly, the quantified evidence node values, and a do-calculus intervention query. Produce a reserve narrative grounded in this causal structure.\u201d", { italics: true }),
      subTitle("3.2", "The 5-Layer Causal DAG"),
      body("The loss development process is encoded as a 5-layer Directed Acyclic Graph. Each layer causally mediates the next:"),
      spacer(80),
      dagTable(),
      spacer(160),
      subTitle("3.3", "The Causal Context Document (CCD)"),
      body("The CCD is an XML document with five structured elements: (1) Metadata \u2014 LOB, accident year, generated_at; (2) CausalSubgraph \u2014 nodes and edges activated by the anomaly; (3) AnomalyContext \u2014 flagged development periods with Z-scores; (4) EvidenceNodes \u2014 observed values for conditioning variables (medical CPI, GDP growth); (5) DoCalculusQuery \u2014 the intervention query specification in Pearl do-calculus notation. Every CCD is SHA-256 hashed and registered in a SQLite audit registry, enabling full reproducibility."),

      // ── SECTION 4: ARCHITECTURE ─────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      sectionTitle("4", "System Architecture"),
      subTitle("4.1", "Five-Module Pipeline"),
      bodyBullet("Module 1 \u2014 Data Ingestion (R / SQLite): Ingests CAS Schedule P CSV data, constructs development triangles, computes ATA factors. Functions: ingest_schedule_p(), parse_triangle_csv(), compute_ata_factors(), initialise_database()."),
      bodyBullet("Module 2 \u2014 Anomaly Detection (R / anomalize): Detects ATA Z-score anomalies (>2.5\u03c3 from column mean) and diagonal effects via linear regression. Functions: detect_ata_zscore(), detect_diagonal_effect(), combine_anomaly_signals()."),
      bodyBullet("Module 3 \u2014 Causal DAG (dagitty / bnlearn): Builds and queries the 5-layer dagitty DAG. Provides do-calculus adjustment sets, directed path queries, and active subgraph extraction. Functions: build_reserving_dag(), query_do_calculus(), extract_active_subgraph()."),
      bodyBullet("Module 4 \u2014 CCD Generator (xml2 / digest): Constructs CCD XML, computes SHA-256, registers in audit DB. Functions: generate_ccd(), build_ccd_xml(), compute_sha256(), register_ccd()."),
      bodyBullet("Module 5 \u2014 LLM Synthesis (Claude API / httr2): Generates reserve narratives via the Anthropic Messages API using the CCD as structured context. Collects RLHF ratings. Functions: synthesize_reserve_narrative(), build_reserve_narrative_prompt(), collect_rlhf_feedback()."),
      subTitle("4.2", "Shiny Dashboard (3-Tab)"),
      bodyBullet("Tab 1 \u2014 Anomaly Overview: plotly ATA heatmap with Z-score colour coding (red >2\u03c3, amber 1\u20132\u03c3, green <1\u03c3), reactable anomaly flags table, summary value boxes."),
      bodyBullet("Tab 2 \u2014 Causal Explorer: visNetwork interactive DAG with anomalous nodes highlighted, counterfactual query launcher, path viewer from any node to ultimate_loss."),
      bodyBullet("Tab 3 \u2014 RLHF Review: CCD-grounded narrative display with SHA-256 audit footer, 5-dimension Likert rating interface, rating history table."),
      subTitle("4.3", "Proof of Technical Readiness"),
      body("A working 5-layer causal pipeline for Solvency II SCR analysis (427 tests, 0 failures) has been implemented using identical architecture, R packages, and Claude API integration. The P&C / Schedule P research is a domain adaptation of that proven system, substantially de-risking the Phase 1 implementation timeline."),

      // ── SECTION 5: EVALUATION ───────────────────────────────────────────
      sectionTitle("5", "Evaluation Framework"),
      subTitle("5.1", "Four Evaluation Dimensions"),
      body("All four dimensions are measured for both the adapted system (CCD + LLM) and the baseline (raw triangle + same LLM), with statistical significance testing where sample sizes permit:"),
      spacer(80),
      evalTable(),
      spacer(160),
      subTitle("5.2", "RLHF Architecture"),
      bodyBullet("Stage 1: Generate paired outputs (baseline and adapted) for 40\u201360 anomaly scenarios across 5\u20138 accident year events."),
      bodyBullet("Stage 2: Present to 4\u20136 FCAS actuaries blind via R Shiny review interface. 1\u20135 Likert ratings with mandatory qualitative justification for scores below 3."),
      bodyBullet("Stage 3: Compile preference data, refine prompts; reward model designed for post-research training."),

      // ── SECTION 6: TEAM ─────────────────────────────────────────────────
      new Paragraph({ children: [new PageBreak()] }),
      sectionTitle("6", "Team Qualifications"),
      body("Principal Investigator \u2014 Arnab Gupta (US): P&C actuarial domain expertise. Lead architect of the working Solvency II causal intelligence system (5-layer pipeline, 427 tests, Claude API integration, dagitty/bnlearn causal DAG). Deep R and causal inference expertise applied to insurance regulatory capital analysis."),
      body("NL Co-Investigators: Actuarial science and causal inference expertise. Lead responsibilities: DAG design and validation, CCD framework implementation, evaluation infrastructure, and RLHF interface development."),
      body("The team has demonstrated prior art in applying causal DAG methodology to insurance regulatory capital analysis. The proposed P&C reserving system directly adapts this proven architecture to a new domain \u2014 reducing implementation risk and strengthening the research foundation."),

      // ── SECTION 7: BUDGET ───────────────────────────────────────────────
      sectionTitle("7", "Budget"),
      subTitle("7.1", "Phase 1 \u2014 CAS Grant (EUR 37,000 / ~$40,000 USD)"),
      budgetTable1(),
      spacer(160),
      subTitle("7.2", "Phase 2 \u2014 Firm Match (EUR 37,000 / ~$40,000 USD)"),
      budgetTable2(),
      spacer(160),
      body("Combined Total: EUR 74,000 (~$80,000 USD). No indirect cost recovery applied."),

      // ── SECTION 8: TIMELINE ─────────────────────────────────────────────
      sectionTitle("8", "Timeline"),
      timelineTable(),
      spacer(160),
      body("Interim Report & Executive Summary due: July 26, 2026. All Final Deliverables due: August 31, 2026."),

      // ── SECTION 9: DELIVERABLES ─────────────────────────────────────────
      sectionTitle("9", "Deliverables (Per CAS RFP)"),
      bodyBullet("Research paper documenting methodology, evaluation results, and findings. Target journal: Variance or CAS E-Forum."),
      bodyBullet("Demonstration cases for 3 Schedule P lines (Workers Compensation primary; 2 additional LOBs in Phase 2)."),
      bodyBullet("System architecture description enabling full reproducibility by any technically proficient actuary."),
      bodyBullet("GitHub repository under MPL 2.0 license: github.com/iarnab/pc-causal-reserving. All R code, DAG specification, CCD generator, test suite (target: 25+ tests), and Shiny dashboard."),
      bodyBullet("Executive summary (1\u20132 pages) for non-technical audiences including CAS leadership."),

      // ── SECTION 10: REFERENCES ──────────────────────────────────────────
      sectionTitle("10", "References"),
      body("CAS Research Working Party on Loss Reserve Uncertainty. (2011). A Public Policy Practice Note: Estimating Loss Reserve Uncertainty. CAS E-Forum."),
      body("Friedland, J. (2010). Estimating Unpaid Claims Using Basic Techniques. Casualty Actuarial Society."),
      body("Pearl, J., Glymour, M., & Jewell, N. P. (2016). Causal Inference in Statistics: A Primer. Wiley."),
      body("Textor, J., van der Zander, B., Gilthorpe, M. S., Liskiewicz, M., & Ellison, G. T. (2016). Robust causal inference using directed acyclic graphs: the R package \u2018dagitty\u2019. International Journal of Epidemiology, 45(6), 1887\u20131894."),
      body("Scutari, M. (2010). Learning Bayesian Networks with the bnlearn R Package. Journal of Statistical Software, 35(3), 1\u201322."),
    ]
  }]
});

Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync("/Users/arnabgupta/cas_research/proposal/CAS2026_Proposal_CausalReserving.docx", buf);
  console.log("Created: CAS2026_Proposal_CausalReserving.docx");
});
