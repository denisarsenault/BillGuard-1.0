// BillGuard browser extension: the toolbar popup.
//
// Reads the text of the page in the current tab when asked, hands it to
// BillGuardBackend (backend.js), and shows what the backend says is captured
// so far. All code finding, the pending pages and the save live in the
// backend; nothing is decided here. The popup is the same in every browser:
// Safari's backend is the BillGuard app's native handler, Chrome's is
// BillGuardChromeExtension/chrome-backend.js.

const api = typeof browser !== "undefined" ? browser : chrome;

const elements = {
    conflicts: document.getElementById("conflicts"),
    conflictSummary: document.getElementById("conflict-summary"),
    conflictList: document.getElementById("conflict-list"),
    empty: document.getElementById("empty"),
    pages: document.getElementById("pages"),
    status: document.getElementById("status"),
    capture: document.getElementById("capture"),
    save: document.getElementById("save"),
    discard: document.getElementById("discard"),
};

let pageCount = 0;
let busy = false;
let discardArmed = false;
let discardTimer = null;

// MARK: Reading the page

/// Runs inside the page (and each frame of it).
function readFrame() {
    return {
        text: document.body ? document.body.innerText : "",
        url: location.href,
        top: window.top === window,
    };
}

async function readPage() {
    const tabs = await api.tabs.query({ active: true, currentWindow: true });
    const tab = tabs && tabs[0];
    if (!tab) {
        throw new Error("No page is open.");
    }

    let results;
    try {
        // Billing portals often show the bill inside a frame.
        results = await api.scripting.executeScript({ target: { tabId: tab.id, allFrames: true }, func: readFrame });
    } catch (error) {
        results = await api.scripting.executeScript({ target: { tabId: tab.id }, func: readFrame });
    }

    const frames = (results || []).map((entry) => entry && entry.result).filter(Boolean);
    frames.sort((a, b) => Number(b.top) - Number(a.top)); // the page itself first
    const seen = new Set();
    const texts = [];
    for (const frame of frames) {
        const text = (frame.text || "").trim();
        if (text && !seen.has(text)) {
            seen.add(text);
            texts.push(text);
        }
    }
    const top = frames.find((frame) => frame.top) || frames[0];
    return { text: texts.join("\n"), url: top ? top.url : "" };
}

// MARK: Showing the result

function plural(count, word) {
    return count + " " + word + (count === 1 ? "" : "s");
}

function showStatus(text, kind) {
    elements.status.hidden = !text;
    elements.status.textContent = text || "";
    elements.status.className = "status" + (kind ? " " + kind : "");
}

function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined) { node.textContent = text; }
    return node;
}

function render(reply) {
    const pages = reply.pages || [];
    const conflicts = reply.conflicts || [];
    pageCount = pages.length;

    elements.pages.replaceChildren(...pages.map((page) => {
        const row = element("li");
        const left = element("div");
        left.append(
            element("div", "page-name", "Page " + page.number),
            element("div", "page-overlaps" + (page.overlaps > 0 ? " some" : ""),
                    plural(page.overlaps, "Overlap") + " Found"));
        row.append(left, element("div", "page-counts", page.diagnoses + " DX / " + page.procedures + " PX"));
        return row;
    }));
    elements.empty.hidden = pages.length > 0;

    elements.conflicts.hidden = conflicts.length === 0;
    elements.conflictSummary.textContent =
        "We detected " + plural(conflicts.length, "diagnostic or procedure code conflict")
        + " across your captured pages. Review " + (conflicts.length === 1 ? "it" : "them") + " before you save.";
    elements.conflictList.replaceChildren(...conflicts.map((conflict) => {
        const row = element("li");
        const pageList = conflict.pages.join(", ");
        row.append(
            element("span", "code", conflict.code),
            document.createTextNode(conflict.kind === "procedure"
                ? " billed on pages " + pageList
                : " on pages " + pageList + ", with no procedure code on at least one"));
        return row;
    }));

    if (reply.error) {
        showStatus(reply.error, "error");
    } else if (reply.message) {
        showStatus(reply.message, reply.saved ? "done" : "");
    }
    updateButtons();
}

function updateButtons() {
    elements.capture.disabled = busy;
    elements.save.disabled = busy || pageCount === 0;
    elements.discard.hidden = pageCount === 0;
    elements.discard.disabled = busy;
    elements.discard.textContent = discardArmed
        ? "Tap Again to Discard " + plural(pageCount, "Page")
        : "Discard Pages";
}

function disarmDiscard() {
    discardArmed = false;
    clearTimeout(discardTimer);
}

/// Runs one action with the buttons off, and shows whatever goes wrong.
async function run(work) {
    if (busy) { return; }
    busy = true;
    updateButtons();
    try {
        render(await work());
    } catch (error) {
        showStatus(error && error.message ? error.message : String(error), "error");
    } finally {
        busy = false;
        updateButtons();
    }
}

// MARK: Actions

elements.capture.addEventListener("click", () => {
    disarmDiscard();
    run(async () => {
        showStatus("Reading this page…");
        let page;
        try {
            page = await readPage();
        } catch (error) {
            throw new Error("BillGuard can't read this page. If the browser asks, allow BillGuard on this website. "
                + "For a PDF or a picture of a bill, use Share and choose BillGuard instead.");
        }
        return BillGuardBackend.ask({ action: "capture", text: page.text, url: page.url });
    });
});

elements.save.addEventListener("click", () => {
    disarmDiscard();
    run(async () => {
        showStatus("Saving to BillGuard…");
        return BillGuardBackend.ask({ action: "save" });
    });
});

elements.discard.addEventListener("click", () => {
    if (!discardArmed) {
        discardArmed = true;
        updateButtons();
        discardTimer = setTimeout(() => { discardArmed = false; updateButtons(); }, 4000);
        return;
    }
    disarmDiscard();
    run(() => BillGuardBackend.ask({ action: "discard" }));
});

run(() => BillGuardBackend.connect());
