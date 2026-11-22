// BillGuard Safari Web Extension: background worker.
//
// The popup talks to the BillGuard app's native handler itself. This worker is
// the fallback for Safari versions where an extension page cannot: it passes a
// popup message on to the native handler and returns the reply.

browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (!request || request.type !== "billguard-native") {
        return false;
    }
    browser.runtime.sendNativeMessage("application.id", request.payload)
        .then((reply) => sendResponse({ reply }))
        .catch((error) => sendResponse({ failure: String(error && error.message ? error.message : error) }));
    return true; // the reply is sent asynchronously
});
