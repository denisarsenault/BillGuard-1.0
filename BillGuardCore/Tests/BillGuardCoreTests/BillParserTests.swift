import XCTest
@testable import BillGuardCore

final class BillParserTests: XCTestCase {

    /// West Volusia account statement — the exact (heavily column-scrambled) OCR
    /// captured on device. Locks in the parser's behavior after extracting it from
    /// the iOS view: charges paired with codes, negatives treated as credits,
    /// Amount Due = charges + credits.
    func testWestVolusiaAccountStatement() {
        let providerText = """
        WEST VOLUSIA MEDICAL ASSOCIAT  1070 NORTH STONE STREET SUITE
        DELAND, FL 32720-0824  CARD NUMBER
        ADDRESS SERVICE REQUESTED  CARDHOLDER NAME
        SIGNATURE
        """
        let procedureText = """
        indicate address or Insurance changes  Tease check dox and usa reverse side to  STATEMENT  RETURN THIS PORTION WITH PAYMENT
        Date  ICPT & Reason  Explanation of Activity  Charges &  Insurance  Payments &  Patient
        Patient:  Mary  M Arsenault  Debits  Pending  Credits  Amount
        Voucher:  2607480
        07/11/11  07/29/11  99214  07132011  Cigna Payment  Office/outpatient Visit  131.00
        07/29/11  07/29/11  07132011  07132011  Cigna Transfer  Cigna Adjustment  - 51.55  0.00
        10/03/11  Master Card  Self Pay Credit Card Pa
        ---- Visit Total  -79.45
        Voucher:  2775530  0.00
        10/03/11  10/18/11  99213  10052011  Cigna Payment  Office/outpatient Visit  88.00
        10/18/11  10/18/11  10052011  10052011  Cigna Transfer  Cigna Adjustment  0.00
        --- Visit Total  -35.26
        52.74
        """

        let result = BillParser(providerText: providerText,
                                procedureText: procedureText).parse()

        // Provider name (billing box + trailing street stripped)
        XCTAssertEqual(result.providerName, "WEST VOLUSIA MEDICAL ASSOCIAT")

        // Two CPT charge rows, paired with their charges
        let charges = result.lineItems.filter { $0.kind == .charge }
        XCTAssertEqual(charges.count, 2, "expected 99214 + 99213")
        XCTAssertEqual(charges.first(where: { $0.code == "99214" })?.amount, 131.00)
        XCTAssertEqual(charges.first(where: { $0.code == "99213" })?.amount, 88.00)
        XCTAssertEqual(charges.reduce(0) { $0 + $1.amount }, 219.00, accuracy: 0.001)

        // Three credits captured (wherever OCR scattered them), all negative
        let credits = result.lineItems.filter { $0.kind == .payment }
        XCTAssertEqual(credits.count, 3)
        let creditsSum = credits.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(creditsSum, -166.26, accuracy: 0.001)
        XCTAssertTrue(credits.allSatisfy { $0.amount < 0 })

        // Amount Due = charges + credits = 219.00 - 166.26 = 52.74
        XCTAssertEqual(result.amountDue, "52.74")

        // No account number / ZIP leaked in as a bogus code
        XCTAssertFalse(result.lineItems.contains { $0.code == "38142" || $0.code == "32720" })
    }

    /// Standard itemized bill must NOT be treated as an account statement,
    /// and a charge amount must pair with its CPT code.
    func testStandardItemizedBill() {
        let procedureText = """
        INPATIENT CHARGES WITH PROCEDURE CODES
        Date  Code  Description  Qty  Amount
        10/10/24  99223  Initial Hospital Care - High  1  $1,450.00
        10/12/24  27447  Total Knee Arthroplasty  1  $22,500.00
        Total Charges:  $23,950.00
        """
        let result = BillParser(procedureText: procedureText).parse()
        let charges = result.lineItems.filter { $0.kind == .charge }
        XCTAssertEqual(charges.first(where: { $0.code == "99223" })?.amount, 1450.00)
        XCTAssertEqual(charges.first(where: { $0.code == "27447" })?.amount, 22500.00,
                       "the thousands-separator amount must not collapse to 22.50")
        XCTAssertTrue(result.lineItems.allSatisfy { $0.kind == .charge },
                      "standard bill should have no payment/credit rows")
    }

    /// A billing modifier printed straight after the code, with no space
    /// ("93976TC"), must not hide the code or end up inside it.
    func testCodesWithGluedModifiers() {
        let procedureText = """
        Date  Code  Description  Qty  Amount
        10/10/24  93976TC  Duplex Scan Limited  1  $412.00
        10/10/24  J1885JW  Ketorolac Injection 15mg  1  $42.00
        10/10/24  73630RT  X-Ray Foot  1  $88.00
        10/10/24  99214  Office Visit  1  $185.00
        Total Charges:  $727.00
        """
        let result = BillParser(procedureText: procedureText).parse()
        let charges = result.lineItems.filter { $0.kind == .charge }
        XCTAssertEqual(charges.first(where: { $0.code == "93976" })?.amount, 412.00)
        XCTAssertEqual(charges.first(where: { $0.code == "J1885" })?.amount, 42.00)
        XCTAssertEqual(charges.first(where: { $0.code == "73630" })?.amount, 88.00)
        XCTAssertEqual(charges.first(where: { $0.code == "99214" })?.amount, 185.00)
        XCTAssertEqual(charges.count, 4, "codes found: \(result.lineItems.map(\.code))")
    }

    /// Seven digits in a row is an ID, and a letter-first code followed by XA
    /// is an undotted ICD-10 code; neither is a code plus a modifier.
    func testLookAlikesAreNotCodesWithModifiers() {
        let procedureText = """
        Date  Code  Description  Qty  Amount
        10/10/24  99214  Office Visit  1  $185.00
        Reference 9397626  T8111XA
        Total Charges:  $185.00
        """
        let result = BillParser(procedureText: procedureText).parse()
        XCTAssertFalse(result.lineItems.contains { $0.code == "93976" || $0.code == "T8111" },
                       "codes found: \(result.lineItems.map(\.code))")
        XCTAssertTrue(result.lineItems.contains { $0.code == "99214" })
    }
}
