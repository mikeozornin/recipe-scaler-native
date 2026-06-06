//
//  GetURLFromPage.js
//  ActionExtension
//
//  JavaScript preprocessing file referenced by NSExtensionJavaScriptPreprocessingFile
//  in the extension's Info.plist. Safari invokes `run()` before opening the
//  extension and forwards the returned dict to the host as
//  NSExtensionJavaScriptPreprocessingResultsKey.
//

var GetURLFromPage = function () {};

GetURLFromPage.prototype = {
    run: function (arguments) {
        arguments.completionFunction({
            "currentUrl": document.URL
        });
    },

    finalize: function (arguments) {
        // No-op; we don't mutate the page after import.
    }
};

// The extension infrastructure expects this global to exist.
var ExtensionPreprocessingJS = new GetURLFromPage;
