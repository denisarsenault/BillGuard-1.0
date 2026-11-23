// BillGuard Chrome extension: billing-code finding.
//
// A JavaScript port of BillGuardShare/BillCodeAnalyzer.swift and the page
// tidying in BillGuardWebExtension/WebCaptureBridge.swift, so the popup can
// show its breakdown and conflict banner without the app. Keep the two in
// step: BillGuardChromeExtension/tests/parity.sh runs the same pages through
// both and compares the results. What is finally saved is worked out again by
// the Swift analyzer when the BillGuard app receives the bill.

const BillGuardAnalyzer = (() => {
    /// Less text than this is a sign-in page or an empty frame, not a bill.
    const minimumPageLength = 80;
    /// The app keeps at most this much of one page.
    const maximumPageLength = 60000;

    const icd10Pattern = /\b[A-Z][0-9][0-9A-Z](?:\.[0-9A-Z]{1,4})?\b/g;
    // Either kind of procedure code (group 1), with a glued-on modifier
    // matched but not captured. See the Swift pattern for the reasoning.
    const procedurePattern =
        /\b([0-9]{5}|[ABCDEGHJKLMPQRSTUV][0-9]{4}(?!X[ADS]\b))(?:[A-Z]{2}|[A-Z][0-9])?\b/g;
    const amountPattern = /\$\s?\d|\b\d{1,3}(?:,\d{3})*\.\d{2}\b/;
    const diagnosisLabelPattern =
        /\b(?:dx|diag\w*|icd(?:-?\s?10)?(?:-cm)?)\b\s*(?:codes?)?\s*[.:#]*\s*(?:[A-Z][0-9][0-9A-Z.]*[,;\s]+)*$/i;
    const zipPrefixPattern =
        /\b(?:AL|AK|AZ|AR|CA|CO|CT|DE|DC|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY)[.,]?\s+$/;
    const identifierLabelPattern =
        /\b(?:account|acct|receipt|invoice|statement|claim|mrn|member|policy|group|subscriber|reference|ref|confirmation|check|zip|box|suite|ste|apt|unit|room|rm|bed|lot|ext|npi|tin|id)\b\s*(?:number|num|no|code)?\s*[.:#]*\s*$/i;
    const codeLabelPattern = /\b(?:cpt|hcpcs|procedures?|proc|codes?)\b\s*(?:codes?)?\s*[.:#]*\s*$/i;
    const partOfNumberAfterPattern = /^(?:\.\d|-\d{4}\b)/;
    const newlines = /\r\n|[\n\r\u000B\u000C\u0085\u2028\u2029]/;

    function unique(codes) {
        return [...new Set(codes)];
    }

    /// A web page's text laid out like the text the analyzer expects: table
    /// cells apart by two spaces, no blank lines, ordinary spaces.
    function tidy(text) {
        const joined = String(text || "")
            .replace(/\u00A0/g, " ")
            .replace(/\t/g, "  ")
            .split(newlines)
            .map((line) => line.trim())
            .filter((line) => line.length > 0)
            .join("\n");
        if (joined.length <= maximumPageLength) {
            return { text: joined, wasCut: false };
        }
        return { text: joined.slice(0, maximumPageLength), wasCut: true };
    }

    /// Procedure codes (CPT and HCPCS) in `text`, in order, repeats included.
    /// A candidate is kept only when it reads as a billed code: it is a known
    /// code, it is labelled as one, or its line carries a charge.
    function procedureCodes(text, knownCodes) {
        const codes = [];
        for (const line of text.split(newlines)) {
            const lineHasCharge = amountPattern.test(line);
            for (const match of line.matchAll(procedurePattern)) {
                const code = match[1];
                const before = line.slice(0, match.index);
                const after = line.slice(match.index + match[0].length);

                const isPartOfNumberOrID = before.endsWith("$") || before.endsWith("$ ")
                    || before.endsWith("-") || partOfNumberAfterPattern.test(after);
                if (isPartOfNumberOrID) { continue; }
                if (zipPrefixPattern.test(before)) { continue; }
                if (identifierLabelPattern.test(before)) { continue; }
                if (diagnosisLabelPattern.test(before)) { continue; }

                if (knownCodes.has(code) || codeLabelPattern.test(before) || lineHasCharge) {
                    codes.push(code);
                }
            }
        }
        return codes;
    }

    /// A page from its text: unique codes in reading order, plus the
    /// procedure codes billed more than once on this same page.
    function makePage(number, rawText, knownCodes) {
        const diagnoses = rawText.match(icd10Pattern) || [];
        const procedures = procedureCodes(rawText, knownCodes);
        const counts = new Map();
        for (const code of procedures) { counts.set(code, (counts.get(code) || 0) + 1); }
        return {
            number,
            rawText,
            diagnoses: unique(diagnoses),
            procedures: unique(procedures),
            overlaps: unique(procedures).filter((code) => counts.get(code) > 1),
        };
    }

    /// Cross-page rule: a procedure code billed on more than one page, and a
    /// diagnosis repeated across pages where one of them has no procedure.
    function conflicts(pages) {
        const found = [];
        for (const code of unique(pages.flatMap((page) => page.procedures))) {
            const hits = pages.filter((page) => page.procedures.includes(code));
            if (hits.length > 1) {
                found.push({ code, kind: "procedure", pages: hits.map((page) => page.number) });
            }
        }
        for (const code of unique(pages.flatMap((page) => page.diagnoses))) {
            const hits = pages.filter((page) => page.diagnoses.includes(code));
            if (hits.length > 1 && hits.some((page) => page.procedures.length === 0)) {
                found.push({ code, kind: "diagnosis", pages: hits.map((page) => page.number) });
            }
        }
        return found;
    }

    return { minimumPageLength, maximumPageLength, tidy, procedureCodes, makePage, conflicts };
})();

if (typeof module !== "undefined") {
    module.exports = BillGuardAnalyzer;
}
