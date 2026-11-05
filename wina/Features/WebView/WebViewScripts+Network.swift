//
//  WebViewScripts+Network.swift
//  wina
//
//  Network hook script for WebView.
//

import Foundation

extension WebViewScripts {
    /// Network hooking script - intercepts fetch and XMLHttpRequest with stack trace capture
    static let networkHook = """
        (function() {
            if (window.__networkHooked) return;
            window.__networkHooked = true;

            // Generate unique request ID
            function generateId() {
                return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
                    var r = Math.random() * 16 | 0;
                    var v = c === 'x' ? r : (r & 0x3 | 0x8);
                    return v.toString(16);
                });
            }

            // Resolve relative URL to absolute URL
            function resolveURL(url) {
                try {
                    return new URL(url, document.baseURI).href;
                } catch(e) {
                    return url;
                }
            }

            // Capture and parse stack trace at request time
            // Supports both Chrome ("at fn (file:line:col)") and Safari ("fn@file:line:col") formats
            function captureStackTrace() {
                try {
                    var stack = new Error().stack || '';
                    var frames = [];
                    var lines = stack.split('\\n');

                    for (var i = 1; i < lines.length && frames.length < 10; i++) {
                        var line = lines[i].trim();
                        if (!line) continue;

                        var functionName = '<anonymous>';
                        var fileName = '';
                        var lineNumber = 0;
                        var columnNumber = 0;

                        // Chrome format: "at functionName (file:line:col)"
                        var chromeMatch = line.match(/^at\\s+(.*?)\\s+\\((.+):(\\d+):(\\d+)\\)$/);
                        if (chromeMatch) {
                            functionName = chromeMatch[1] || '<anonymous>';
                            fileName = chromeMatch[2];
                            lineNumber = parseInt(chromeMatch[3]);
                            columnNumber = parseInt(chromeMatch[4]);
                        } else {
                            // Chrome anonymous: "at file:line:col"
                            var chromeAnon = line.match(/^at\\s+(.+):(\\d+):(\\d+)$/);
                            if (chromeAnon) {
                                fileName = chromeAnon[1];
                                lineNumber = parseInt(chromeAnon[2]);
                                columnNumber = parseInt(chromeAnon[3]);
                            } else {
                                // Safari format: "functionName@file:line:col" or "@file:line:col"
                                var safariMatch = line.match(/^(.*)@(.+):(\\d+):(\\d+)$/);
                                if (safariMatch) {
                                    functionName = safariMatch[1] || '<anonymous>';
                                    fileName = safariMatch[2];
                                    lineNumber = parseInt(safariMatch[3]);
                                    columnNumber = parseInt(safariMatch[4]);
                                }
                            }
                        }

                        if (fileName) {
                            // Skip our own hook functions
                            if (fileName.includes('captureStackTrace') ||
                                functionName === 'captureStackTrace' ||
                                functionName.includes('__network')) {
                                continue;
                            }

                            try {
                                fileName = new URL(fileName, document.baseURI).href;
                            } catch(e) {}

                            frames.push({
                                functionName: functionName,
                                fileName: fileName,
                                lineNumber: lineNumber,
                                columnNumber: columnNumber
                            });
                        }
                    }
                    return frames;
                } catch(e) {
                    return [];
                }
            }

            // Safely stringify headers
            function headersToObject(headers) {
                if (!headers) return null;
                var obj = Object.create(null);
                if (Array.isArray(headers)) {
                    // Do not consume a custom iterator before the native fetch reads it.
                    var pairs = [];
                    for (var i = 0; i < headers.length; i++) {
                        var pair = headers[i];
                        if (!Array.isArray(pair) || pair.length !== 2 ||
                            typeof pair[0] !== 'string' || typeof pair[1] !== 'string') return null;
                        pairs.push([pair[0], pair[1]]);
                    }
                    headers = new Headers(pairs);
                }
                if (typeof headers.forEach === 'function') {
                    headers.forEach(function(value, key) { obj[key] = value; });
                } else if (typeof headers === 'object') {
                    Object.keys(headers).forEach(function(key) { obj[key] = headers[key]; });
                }
                return Object.keys(obj).length > 0 ? obj : null;
            }

            // FormData를 사람 읽기 쉬운 key=value 문자열로 변환합니다.
            function formatFormData(formData) {
                if (!formData || !formData.forEach) return null;
                var pairs = [];
                formData.forEach(function(value, key) {
                    if (typeof File !== 'undefined' && value instanceof File) {
                        pairs.push(key + '=[File:' + value.name + ', ' + value.size + ' bytes]');
                    } else if (typeof Blob !== 'undefined' && value instanceof Blob) {
                        pairs.push(key + '=[Blob:' + (value.type || 'application/octet-stream') + ', ' + value.size + ' bytes]');
                    } else {
                        pairs.push(key + '=' + String(value));
                    }
                });
                return pairs.join('&');
            }

            // 다양한 Request body 타입을 문자열로 직렬화합니다.
            function serializeBody(body) {
                if (body === null || body === undefined) return null;
                if (typeof body === 'string') return body;

                if (typeof URLSearchParams !== 'undefined' && body instanceof URLSearchParams) {
                    return body.toString();
                }

                if (typeof FormData !== 'undefined' && body instanceof FormData) {
                    return formatFormData(body);
                }

                if (typeof File !== 'undefined' && body instanceof File) {
                    return '[File:' + body.name + ', ' + body.size + ' bytes, ' + (body.type || 'application/octet-stream') + ']';
                }

                if (typeof Blob !== 'undefined' && body instanceof Blob) {
                    return '[Blob:' + (body.type || 'application/octet-stream') + ', ' + body.size + ' bytes]';
                }

                if (typeof ArrayBuffer !== 'undefined' && body instanceof ArrayBuffer) {
                    return '[ArrayBuffer ' + body.byteLength + ' bytes]';
                }

                if (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView && ArrayBuffer.isView(body)) {
                    return '[' + Object.prototype.toString.call(body).slice(8, -1) + ' ' + body.byteLength + ' bytes]';
                }

                if (typeof ReadableStream !== 'undefined' && body instanceof ReadableStream) {
                    return 'ReadableStream';
                }

                try { return JSON.stringify(body); } catch(e) {}
                return String(body);
            }

            // Truncate body for large payloads
            function truncateBody(body, maxLen) {
                maxLen = maxLen || 10000;
                var serialized = serializeBody(body);
                if (serialized === null || serialized === undefined) return null;
                if (serialized.length > maxLen) {
                    return serialized.substring(0, maxLen) + '... (truncated)';
                }
                return serialized;
            }

            // init.body가 비어 있는 fetch(Request) 패턴도 보존하기 위해 Request 본문을 별도로 읽습니다.
            function captureRequestBody(input, init) {
                var hasInitBody = init && Object.prototype.hasOwnProperty.call(init, 'body');
                if (hasInitBody) {
                    return Promise.resolve(truncateBody(init.body));
                }

                if (typeof Request !== 'undefined' && input instanceof Request) {
                    if (input.bodyUsed) {
                        return Promise.resolve('[Body already consumed]');
                    }

                    var contentType = '';
                    try {
                        contentType = (input.headers && input.headers.get && input.headers.get('content-type')) || '';
                        contentType = contentType.toLowerCase();
                    } catch(e) {}

                    try {
                        if ((contentType.indexOf('multipart/form-data') >= 0 ||
                             contentType.indexOf('application/x-www-form-urlencoded') >= 0) &&
                            typeof input.formData === 'function') {
                            return input.clone().formData()
                                .then(function(formData) {
                                    return truncateBody(formatFormData(formData));
                                })
                                .catch(function() {
                                    return input.clone().text().then(function(text) {
                                        if (text && text.length > 0) {
                                            return truncateBody(text);
                                        }
                                        return truncateBody(input.body);
                                    }).catch(function() {
                                        return truncateBody(input.body);
                                    });
                                });
                        }

                        return input.clone().text()
                            .then(function(text) {
                                if (text && text.length > 0) {
                                    return truncateBody(text);
                                }
                                return truncateBody(input.body);
                            })
                            .catch(function() {
                                return truncateBody(input.body);
                            });
                    } catch(e) {
                        return Promise.resolve(truncateBody(input.body));
                    }
                }

                var fallbackBody = (input && typeof input === 'object' && 'body' in input) ? input.body : null;
                return Promise.resolve(truncateBody(fallbackBody));
            }

            // Hook fetch
            var originalFetch = window.fetch;
            window.fetch = function(input, init) {
                var requestId = generateId();
                var rawUrl = typeof input === 'string' ? input : (input.url || String(input));
                var url = resolveURL(rawUrl);
                var method = (init && init.method) || (input && input.method) || 'GET';
                var headers = (init && init.headers) || (input && input.headers) || null;
                var hasInitBody = init && Object.prototype.hasOwnProperty.call(init, 'body');
                var immediateBody = hasInitBody ? truncateBody(init.body) : truncateBody(input && input.body);
                var requestBodyPromise = captureRequestBody(input, init).catch(function() {
                    return immediateBody;
                });
                var stackFrames = captureStackTrace();

                try {
                    window.webkit.messageHandlers.networkRequest.postMessage({
                        action: 'start',
                        id: requestId,
                        method: method,
                        url: url,
                        type: 'fetch',
                        headers: headersToObject(headers),
                        body: immediateBody,
                        stackFrames: stackFrames,
                        initiatorFunction: stackFrames.length > 0 ? stackFrames[0].functionName : null
                    });
                } catch(e) {}

                // request body 추출이 늦게 끝나면 별도 이벤트로 본문만 보강합니다.
                requestBodyPromise.then(function(resolvedBody) {
                    if (!resolvedBody || resolvedBody === immediateBody) return;
                    try {
                        window.webkit.messageHandlers.networkRequest.postMessage({
                            action: 'requestBody',
                            id: requestId,
                            body: resolvedBody
                        });
                    } catch(e) {}
                }).catch(function() {});

                return originalFetch.apply(this, arguments)
                    .then(function(response) {
                        var responseHeaders = {};
                        response.headers.forEach(function(value, key) {
                            responseHeaders[key] = value;
                        });

                        // Clone response to read body
                        var cloned = response.clone();
                        var responseBodyPromise = cloned.text()
                            .then(function(text) { return truncateBody(text); })
                            .catch(function() { return null; });

                        responseBodyPromise.then(function(responseBody) {
                            try {
                                window.webkit.messageHandlers.networkRequest.postMessage({
                                    action: 'complete',
                                    id: requestId,
                                    status: response.status,
                                    statusText: response.statusText,
                                    headers: responseHeaders,
                                    body: responseBody,
                                    requestBody: immediateBody
                                });
                            } catch(e) {}
                        });

                        return response;
                    })
                    .catch(function(error) {
                        try {
                            window.webkit.messageHandlers.networkRequest.postMessage({
                                action: 'error',
                                id: requestId,
                                error: error.message || String(error),
                                requestBody: immediateBody
                            });
                        } catch(e) {}
                        throw error;
                    });
            };

            // Hook XMLHttpRequest
            var XHR = XMLHttpRequest;
            var originalOpen = XHR.prototype.open;
            var originalSend = XHR.prototype.send;
            var originalSetRequestHeader = XHR.prototype.setRequestHeader;

            XHR.prototype.open = function(method, url) {
                this.__networkRequestId = generateId();
                this.__networkMethod = method;
                this.__networkUrl = resolveURL(url);
                this.__networkHeaders = {};
                return originalOpen.apply(this, arguments);
            };

            XHR.prototype.setRequestHeader = function(name, value) {
                if (this.__networkHeaders) {
                    this.__networkHeaders[name] = value;
                }
                return originalSetRequestHeader.apply(this, arguments);
            };

            XHR.prototype.send = function(body) {
                var xhr = this;
                var requestId = xhr.__networkRequestId;
                var stackFrames = captureStackTrace();

                try {
                    window.webkit.messageHandlers.networkRequest.postMessage({
                        action: 'start',
                        id: requestId,
                        method: xhr.__networkMethod || 'GET',
                        url: xhr.__networkUrl || '',
                        type: 'xhr',
                        headers: xhr.__networkHeaders,
                        body: truncateBody(body),
                        stackFrames: stackFrames,
                        initiatorFunction: stackFrames.length > 0 ? stackFrames[0].functionName : null
                    });
                } catch(e) {}

                function onLoad() {
                    removeListeners();
                    var responseHeaders = Object.create(null);
                    var headerString = xhr.getAllResponseHeaders();
                    if (headerString) {
                        headerString.split('\\r\\n').forEach(function(line) {
                            var separator = line.indexOf(':');
                            if (separator > 0) {
                                responseHeaders[line.slice(0, separator)] = line.slice(separator + 1).trim();
                            }
                        });
                    }

                    var responseBody = null;
                    try {
                        if (!xhr.responseType || xhr.responseType === 'text') {
                            responseBody = truncateBody(xhr.responseText);
                        } else if (xhr.responseType === 'json') {
                            responseBody = truncateBody(JSON.stringify(xhr.response));
                        } else if (xhr.responseType === 'document') {
                            responseBody = xhr.responseXML ? truncateBody(new XMLSerializer().serializeToString(xhr.responseXML)) : null;
                        } else {
                            responseBody = truncateBody(xhr.response);
                        }
                    } catch(e) {}

                    try {
                        window.webkit.messageHandlers.networkRequest.postMessage({
                            action: 'complete',
                            id: requestId,
                            status: xhr.status,
                            statusText: xhr.statusText,
                            headers: Object.keys(responseHeaders).length > 0 ? responseHeaders : null,
                            body: responseBody
                        });
                    } catch(e) {}
                }

                function onError() {
                    removeListeners();
                    try {
                        window.webkit.messageHandlers.networkRequest.postMessage({
                            action: 'error',
                            id: requestId,
                            error: 'Network error'
                        });
                    } catch(e) {}
                }

                function onAbort() {
                    removeListeners();
                    try {
                        window.webkit.messageHandlers.networkRequest.postMessage({
                            action: 'error',
                            id: requestId,
                            error: 'Request aborted'
                        });
                    } catch(e) {}
                }

                function onTimeout() {
                    removeListeners();
                    try {
                        window.webkit.messageHandlers.networkRequest.postMessage({
                            action: 'error',
                            id: requestId,
                            error: 'Request timeout'
                        });
                    } catch(e) {}
                }

                function removeListeners() {
                    xhr.removeEventListener('load', onLoad);
                    xhr.removeEventListener('error', onError);
                    xhr.removeEventListener('abort', onAbort);
                    xhr.removeEventListener('timeout', onTimeout);
                }

                xhr.addEventListener('load', onLoad);
                xhr.addEventListener('error', onError);
                xhr.addEventListener('abort', onAbort);
                xhr.addEventListener('timeout', onTimeout);
                try {
                    return originalSend.apply(this, arguments);
                } catch (error) {
                    removeListeners();
                    try {
                        window.webkit.messageHandlers.networkRequest.postMessage({
                            action: 'error', id: requestId, error: String(error)
                        });
                    } catch(e) {}
                    throw error;
                }
            };
        })();
        """
}
