const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, BorderStyle, WidthType,
  ShadingType, PageNumber, LevelFormat, ExternalHyperlink
} = require("docx");
const fs = require("fs");

const CAS_BLUE   = "003087";
const LIGHT_BLUE = "D5E8F0";
const MID_BLUE   = "B8D4E8";
const WHITE      = "FFFFFF";
const LIGHT_GREY = "F5F5F5";
const TEXT_GREY  = "333333";

const border = (color = "CCCCCC") => ({ style: BorderStyle.SINGLE, size: 1, color });
const cellBorders = (color = "CCCCCC") => ({
  top: border(color), bottom: border(color),
  left: border(color), right: border(color)
});

const CONTENT_W = 9360;

const body = (text, opts = {}) => new Paragraph({
  spacing: { before: 60, after: 140, line: 280 },
  children: [new TextRun({ text, font: "Arial", size: 20, color: TEXT_GREY, ...opts })]
});

const bullet = (text) => new Paragraph({
  numbering: { reference: "bullets", level: 0 },
  spacing: { before: 40, after: 80 },
  children: [new TextRun({ text, font: "Arial", size: 20, color: TEXT_GREY })]
});

const section = (text) => new Paragraph({
  spacing: { before: 240, after: 100 },
  border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: CAS_BLUE, space: 1 } },
  children: [new TextRun({ text: text.toUpperCase(), bold: true, font: "Arial", size: 22, color: CAS_BLUE })]
});

const spacer = (pts = 100) => new Paragraph({ spacing: { before: 0, after: pts }, children: [] });

// Budget summary table
const BUD_COLS = [3000, 3000, 3360]; // sum = 9360
function budgetSummary() {
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA },
    columnWidths: BUD_COLS,
    rows: [
      new TableRow({ tableHeader: true, children: [
        new TableCell({ borders: cellBorders(CAS_BLUE), width: { size: BUD_COLS[0], type: WidthType.DXA },
          shading: { fill: CAS_BLUE, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "Component", bold: true, font: "Arial", size: 18, color: WHITE })] })] }),
        new TableCell({ borders: cellBorders(CAS_BLUE), width: { size: BUD_COLS[1], type: WidthType.DXA },
          shading: { fill: CAS_BLUE, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "EUR", bold: true, font: "Arial", size: 18, color: WHITE })] })] }),
        new TableCell({ borders: cellBorders(CAS_BLUE), width: { size: BUD_COLS[2], type: WidthType.DXA },
          shading: { fill: CAS_BLUE, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "USD (approx.)", bold: true, font: "Arial", size: 18, color: WHITE })] })] }),
      ]}),
      new TableRow({ children: [
        new TableCell({ borders: cellBorders(), width: { size: BUD_COLS[0], type: WidthType.DXA },
          margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "Phase 1 \u2014 CAS Grant (185 NL hrs)", font: "Arial", size: 18, color: TEXT_GREY })] })] }),
        new TableCell({ borders: cellBorders(), width: { size: BUD_COLS[1], type: WidthType.DXA },
          margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "37,000", font: "Arial", size: 18, color: TEXT_GREY })] })] }),
        new TableCell({ borders: cellBorders(), width: { size: BUD_COLS[2], type: WidthType.DXA },
          margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "~$40,000", font: "Arial", size: 18, color: TEXT_GREY })] })] }),
      ]}),
      new TableRow({ children: [
        new TableCell({ borders: cellBorders(), width: { size: BUD_COLS[0], type: WidthType.DXA },
          shading: { fill: LIGHT_GREY, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "Phase 2 \u2014 Firm Match (overhead + US hrs)", font: "Arial", size: 18, color: TEXT_GREY })] })] }),
        new TableCell({ borders: cellBorders(), width: { size: BUD_COLS[1], type: WidthType.DXA },
          shading: { fill: LIGHT_GREY, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "37,000", font: "Arial", size: 18, color: TEXT_GREY })] })] }),
        new TableCell({ borders: cellBorders(), width: { size: BUD_COLS[2], type: WidthType.DXA },
          shading: { fill: LIGHT_GREY, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "~$40,000", font: "Arial", size: 18, color: TEXT_GREY })] })] }),
      ]}),
      new TableRow({ children: [
        new TableCell({ borders: cellBorders(CAS_BLUE), width: { size: BUD_COLS[0], type: WidthType.DXA },
          shading: { fill: MID_BLUE, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "TOTAL", bold: true, font: "Arial", size: 18, color: CAS_BLUE })] })] }),
        new TableCell({ borders: cellBorders(CAS_BLUE), width: { size: BUD_COLS[1], type: WidthType.DXA },
          shading: { fill: MID_BLUE, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "74,000", bold: true, font: "Arial", size: 18, color: CAS_BLUE })] })] }),
        new TableCell({ borders: cellBorders(CAS_BLUE), width: { size: BUD_COLS[2], type: WidthType.DXA },
          shading: { fill: MID_BLUE, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "~$80,000", bold: true, font: "Arial", size: 18, color: CAS_BLUE })] })] }),
      ]}),
    ]
  });
}

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
    default: { document: { run: { font: "Arial", size: 20, color: TEXT_GREY } } }
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
            new TextRun({ text: "EXECUTIVE SUMMARY \u2014 CAS 2026 RFP Submission", font: "Arial", size: 16, color: "888888" }),
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
          children: [new TextRun({ text: "Submitted March 27, 2026  |  Arnab Gupta  |  esmith@casact.org & hdavis@casact.org  |  Subject: LLM AI Research Proposal", font: "Arial", size: 16, color: "888888" })]
        })
      ]})
    },
    children: [
      // Title block
      new Paragraph({ spacing: { before: 400, after: 120 },
        children: [new TextRun({ text: "Causal Intelligence for P&C Loss Reserving", font: "Arial", size: 44, bold: true, color: CAS_BLUE })] }),
      new Paragraph({ spacing: { before: 0, after: 80 },
        children: [new TextRun({ text: "Executive Summary  \u2014  CAS 2026 LLM Research Proposal", font: "Arial", size: 22, color: "555555" })] }),
      new Paragraph({ spacing: { before: 0, after: 300 },
        border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: CAS_BLUE, space: 1 } },
        children: [new TextRun({ text: "Arnab Gupta (US) \u00B7 NL Co-Investigators  |  Workers Compensation / Schedule P  |  April \u2013 August 2026", font: "Arial", size: 18, color: "777777" })] }),
      spacer(160),

      // Problem
      section("The Problem"),
      body("Current LLMs deployed in P&C loss reserving describe triangle patterns \u2014 but cannot reason causally. They cannot distinguish adverse development caused by medical cost inflation from that caused by tort reform or case reserve under-adequacy. This makes LLM reserve narratives unauditable, non-reproducible, and unsuitable for actuarial reliance."),

      // Solution
      spacer(80),
      section("Our Solution"),
      body("We build a five-module R pipeline that grounds every LLM reserve narrative in an explicit causal Directed Acyclic Graph (DAG) of the loss development process. The core innovation is the Causal Context Document (CCD) \u2014 a SHA-256-registered XML document injected into every Claude API prompt, encoding:"),
      bullet("The active causal subgraph (nodes and edges activated by the detected anomaly)"),
      bullet("Quantified evidence node values (medical CPI, GDP growth, unemployment rate)"),
      bullet("A do-calculus intervention query specifying the counterfactual scenario"),
      spacer(80),
      body("This moves the LLM from pattern description to causal attribution \u2014 narratives that are traceable to specific DAG nodes and reproducible run-to-run."),

      // Deliverables
      spacer(80),
      section("What We Will Deliver"),
      bullet("Research paper \u2014 methodology, evaluation results, findings (target: Variance or CAS E-Forum)"),
      bullet("Demonstration cases \u2014 3 Schedule P lines, starting with Workers Compensation (1988\u20131997)"),
      bullet("System architecture document \u2014 reproducible by any technically proficient actuary"),
      bullet("Open-source GitHub repository (MPL 2.0): github.com/iarnab/pc-causal-reserving"),
      bullet("Executive summary (this document) for non-technical CAS audiences"),

      // Why this team
      spacer(80),
      section("Why This Team"),
      body("We have already built a working 5-layer causal intelligence pipeline for Solvency II SCR analysis using identical architecture (dagitty DAG, Claude API, R Shiny, 427 automated tests). The P&C reserving system is a domain adaptation of a proven system \u2014 not a greenfield build. This substantially de-risks the timeline and demonstrates both technical readiness and actuarial domain credibility."),

      // Budget
      spacer(80),
      section("Budget Summary"),
      spacer(80),
      budgetSummary(),
      spacer(160),
      body("Phase 1 (CAS grant) funds core NL research deliverables. Phase 2 (firm match) enables US/NL co-investigator model, extended evaluation, and conference dissemination. No indirect cost recovery applied."),

      // Contact
      spacer(160),
      section("Submission Details"),
      body("Submit to: Elizabeth Smith (esmith@casact.org) and Heather Davis (hdavis@casact.org)"),
      body("Subject line: \u201cLLM AI Research Proposal\u201d"),
      body("Deadline: Friday, March 27, 2026"),
      spacer(80),
      new Paragraph({ spacing: { before: 80, after: 80 },
        children: [new ExternalHyperlink({ link: "https://github.com/iarnab/pc-causal-reserving",
          children: [new TextRun({ text: "github.com/iarnab/pc-causal-reserving", font: "Arial", size: 20, style: "Hyperlink" })] })] }),
    ]
  }]
});

Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync("/Users/arnabgupta/cas_research/proposal/CAS2026_ExecutiveSummary.docx", buf);
  console.log("Created: CAS2026_ExecutiveSummary.docx");
});
