// BillGuard Chrome extension: the popup's backend.
//
// Chrome cannot reach the BillGuard app's native handler the way Safari does,
// so the work is done here: codes are found with analyzer.js, the pending
// pages are kept in the extension's own storage on this computer, and Save
// hands the bill to the BillGuard Mac app through a billguard:// link. The
// app shows the bill for review and saves it to iCloud; nothing is saved
// without that step. Defines BillGuardBackend, the interface popup.js uses.
//
// build.sh joins known-codes, analyzer.js and this file into backend.js.

const BillGuardBackend = (() => {
    const storageKey = "pendingBill";
    /// Longest bill, in characters of page text, that is sent in one link.
    const maximumHandoffLength = 200000;
    const knownCodes = new Set(typeof BILLGUARD_KNOWN_CODES !== "undefined" ? BILLGUARD_KNOWN_CODES : []);

    async function load() {
        const stored = await chrome.storage.local.get(storageKey);
        const bill = stored[storageKey];
        return bill && Array.isArray(bill.pages) ? bill : { sourceURL: null, pages: [] };
    }

    async function store(bill) {
        await chrome.storage.local.set({ [storageKey]: bill });
    }

    /// What popup.js renders: the same shape the Safari handler answers with.
    function reply(bill, extra) {
        return Object.assign({
            pages: bill.pages.map((page) => ({
                number: page.number,
                diagnoses: page.diagnoses.length,
                procedures: page.procedures.length,
                overlaps: page.overlaps.length,
            })),
            conflicts: BillGuardAnalyzer.conflicts(bill.pages),
            saved: false,
        }, extra || {});
    }

    function isWebAddress(url) {
        return /^https?:\/\//i.test(url || "");
    }

    async function capture(bill, text, url) {
        const tidied = BillGuardAnalyzer.tidy(text);
        if (!tidied.text) {
            return reply(bill, { error: "No readable text was found on this page. For a PDF or a picture of a bill, "
                + "save it and share it to BillGuard from Finder or Preview instead." });
        }
        if (tidied.text.length < BillGuardAnalyzer.minimumPageLength) {
            return reply(bill, { error: "This page has too little text to be a bill." });
        }
        if (bill.pages.some((page) => page.rawText === tidied.text)) {
            return reply(bill, { message: "This page was already captured, so it was not added again." });
        }

        const page = BillGuardAnalyzer.makePage(bill.pages.length + 1, tidied.text, knownCodes);
        bill.pages.push(page);
        if (!bill.sourceURL && isWebAddress(url)) {
            bill.sourceURL = url;
        }
        await store(bill);

        let message = "Added page " + page.number + ".";
        if (page.diagnoses.length === 0 && page.procedures.length === 0) {
            message += " No billing codes were found on it.";
        }
        if (tidied.wasCut) {
            message += " The page was very long, so only the first part was kept.";
        }
        return reply(bill, { message });
    }

    function base64URL(text) {
        const bytes = new TextEncoder().encode(text);
        let binary = "";
        for (let start = 0; start < bytes.length; start += 0x8000) {
            binary += String.fromCharCode.apply(null, bytes.subarray(start, start + 0x8000));
        }
        return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    }

    /// The link that hands the bill to the BillGuard Mac app. Only the page
    /// text travels: the app finds the codes again itself.
    function handoffURL(bill) {
        const payload = { v: 1, sourceURL: bill.sourceURL || null, pages: bill.pages.map((page) => page.rawText) };
        return "billguard://web-capture?d=" + base64URL(JSON.stringify(payload));
    }

    async function save(bill) {
        if (bill.pages.length === 0) {
            return reply(bill, { error: "Add a page before saving." });
        }
        const length = bill.pages.reduce((total, page) => total + page.rawText.length, 0);
        if (length > maximumHandoffLength) {
            return reply(bill, { error: "This bill is too long to send in one go. Discard it and capture fewer pages at a time." });
        }

        const url = handoffURL(bill);
        try {
            // Asking the current tab to open the link makes Chrome offer to
            // open BillGuard; the tab itself stays where it is.
            const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
            await chrome.tabs.update(tabs[0].id, { url });
        } catch (error) {
            window.open(url);
        }
        return reply(bill, { message: "Sent to the BillGuard app. Allow Chrome to open it, then review and save the bill there. "
            + "Once it is under Web Captures, choose Discard Pages here to start a new bill." });
    }

    async function ask(payload) {
        const bill = await load();
        switch (payload.action) {
        case "state":
            return reply(bill);
        case "capture":
            return capture(bill, payload.text, payload.url);
        case "save":
            return save(bill);
        case "discard":
            await chrome.storage.local.remove(storageKey);
            return reply({ sourceURL: null, pages: [] }, { message: "Captured pages discarded." });
        default:
            throw new Error("Unknown request.");
        }
    }

    return { connect: () => ask({ action: "state" }), ask, handoffURL };
})();

if (typeof module !== "undefined") {
    module.exports = BillGuardBackend;
}
