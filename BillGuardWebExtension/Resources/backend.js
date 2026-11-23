// BillGuard Safari Web Extension: the popup's backend.
//
// Passes each popup request to the BillGuard app's native handler
// (SafariWebExtensionHandler.swift), which does the code finding, keeps the
// pending pages and saves to iCloud. Defines BillGuardBackend, the interface
// popup.js uses; the Chrome extension ships a different backend.js.

const BillGuardBackend = (() => {
    const api = typeof browser !== "undefined" ? browser : chrome;

    /// "direct" once the popup has reached the handler itself, "relay" when it
    /// has to go through the background worker.
    let transport = null;

    async function sendDirect(payload) {
        return api.runtime.sendNativeMessage("application.id", payload);
    }

    async function sendRelayed(payload) {
        const answer = await api.runtime.sendMessage({ type: "billguard-native", payload });
        if (answer && answer.reply) {
            return answer.reply;
        }
        throw new Error(answer && answer.failure ? answer.failure : "BillGuard did not answer.");
    }

    function isReply(value) {
        return value && typeof value === "object" && Array.isArray(value.pages);
    }

    /// Picks the transport with a request that changes nothing, so that a
    /// request that adds a page is never sent twice. Returns the pending bill.
    async function connect() {
        try {
            const reply = await sendDirect({ action: "state" });
            if (isReply(reply)) {
                transport = "direct";
                return reply;
            }
        } catch (error) {
            // Fall through to the background worker.
        }
        const reply = await sendRelayed({ action: "state" });
        if (!isReply(reply)) {
            throw new Error("BillGuard did not answer.");
        }
        transport = "relay";
        return reply;
    }

    async function ask(payload) {
        const reply = transport === "direct" ? await sendDirect(payload) : await sendRelayed(payload);
        if (!isReply(reply)) {
            throw new Error("BillGuard did not answer.");
        }
        return reply;
    }

    return { connect, ask };
})();
