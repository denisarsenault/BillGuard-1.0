// Prints, for each page text in cases.json, what the JavaScript analyzer makes
// of it, in the same form as parity.swift.
const fs = require("fs");
const path = require("path");
const analyzer = require("../analyzer.js");

const cases = JSON.parse(fs.readFileSync(path.join(__dirname, "cases.json"), "utf8"));
const known = new Set(JSON.parse(fs.readFileSync(process.argv[2], "utf8"))
    .map((entry) => entry.code)
    .filter((code) => /^(?:[0-9]{5}|[ABCDEGHJKLMPQRSTUV][0-9]{4})$/.test(code)));

const pages = cases.map((text, index) => {
    const tidied = analyzer.tidy(text);
    const page = analyzer.makePage(index + 1, tidied.text, known);
    return Object.assign(page, { wasCut: tidied.wasCut });
});

function sorted(value) {
    if (Array.isArray(value)) { return value.map(sorted); }
    if (value && typeof value === "object") {
        return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sorted(value[key])]));
    }
    return value;
}

console.log(JSON.stringify(sorted({
    known: known.size,
    pages: pages.map((page) => ({ text: page.rawText, wasCut: page.wasCut, diagnoses: page.diagnoses,
                                  procedures: page.procedures, overlaps: page.overlaps })),
    conflicts: analyzer.conflicts(pages),
}), null, 2));
