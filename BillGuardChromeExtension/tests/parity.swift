// Prints, for each page text in cases.json, what the Swift analyzer makes of
// it. parity.sh compares this with parity.js.
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let cases = try JSONDecoder().decode([String].self, from: Data(contentsOf: directory.appendingPathComponent("cases.json")))
let known = KnownProcedureCodes.load(from: URL(fileURLWithPath: CommandLine.arguments[2]))

var results: [[String: Any]] = []
var pages: [MedicalBillPage] = []
for (index, text) in cases.enumerated() {
    let tidied = WebCaptureBridge.tidy(text)
    let page = BillCodeAnalyzer.makePage(number: index + 1, rawText: tidied.text, knownCodes: known)
    pages.append(page)
    results.append(["text": tidied.text, "wasCut": tidied.wasCut,
                    "diagnoses": page.identifiedDiagnosticCodes,
                    "procedures": page.identifiedProcedureCodes,
                    "overlaps": page.overlappingCodes])
}
let conflicts = BillCodeAnalyzer.crossPageAnomalies(in: pages).map {
    ["code": $0.code, "kind": $0.kind == .duplicateProcedure ? "procedure" : "diagnosis", "pages": $0.pageNumbers] as [String: Any]
}
let output: [String: Any] = ["known": known.count, "pages": results, "conflicts": conflicts]
print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted]), encoding: .utf8)!)
