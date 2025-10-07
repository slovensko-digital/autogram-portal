(function() {
    window.agp = {
        // Initialize iframe with options
        initIframe: function (sessionId, options = {}) {
            const config = {
                mode: options.mode || 'iframe', // 'iframe' or 'popup'
                parentElement: options.parentElement || null,
                noPreview: options.noPreview || false,
                width: options.width || '100%',
                height: options.height || '800px',
                border: options.border || 'solid 1px #ccc',
                baseUrl: options.baseUrl || window.location.origin,
                popupWidth: options.popupWidth || 800,
                popupHeight: options.popupHeight || 600,
                popupTitle: options.popupTitle || 'AGP Portal',
                onMessage: options.onMessage || null,
                onClose: options.onClose || null
            };

            if (config.mode === 'popup') {
                return this._createPopup(sessionId, config);
            } else {
                return this._createIframe(sessionId, config);
            }
        },

        // Create iframe mode
        _createIframe: function (sessionId, config) {
            const iframe = document.createElement('iframe');
            iframe.src = `${config.baseUrl}/contracts/${sessionId}/iframe` + (config.noPreview ? '?no_preview=1' : '');
            iframe.style.width = config.width;
            iframe.style.height = config.height;
            iframe.style.border = config.border;
            iframe.setAttribute('data-agp-session', sessionId);

            // Set up message listener
            this._setupMessageListener(config, iframe);

            // Append to specified parent or body
            const targetElement = config.parentElement || document.body;
            if (typeof targetElement === 'string') {
                const element = document.querySelector(targetElement);
                if (element) {
                    element.appendChild(iframe);
                } else {
                    console.error('AGP: Parent element not found:', targetElement);
                    document.body.appendChild(iframe);
                }
            } else {
                targetElement.appendChild(iframe);
            }

            return {
                iframe: iframe,
                destroy: function() {
                    if (iframe.parentNode) {
                        iframe.parentNode.removeChild(iframe);
                    }
                }
            };
        },

        // Create popup mode
        _createPopup: function (sessionId, config) {
            const popup = document.createElement('div');
            popup.style.cssText = `
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background: rgba(0, 0, 0, 0.7);
                z-index: 10000;
                display: flex;
                justify-content: center;
                align-items: center;
            `;
            popup.setAttribute('data-agp-popup', sessionId);

            const popupContent = document.createElement('div');
            popupContent.style.cssText = `
                background: white;
                border-radius: 8px;
                box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
                position: relative;
                width: ${config.popupWidth}px;
                height: ${config.popupHeight}px;
                max-width: 90vw;
                max-height: 90vh;
                display: flex;
                flex-direction: column;
            `;

            // Create header with close button
            const header = document.createElement('div');
            header.style.cssText = `
                padding: 16px 20px;
                border-bottom: 1px solid #e1e1e1;
                display: flex;
                justify-content: space-between;
                align-items: center;
                background: #f8f9fa;
                border-radius: 8px 8px 0 0;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            `;

            const title = document.createElement('h3');
            title.textContent = config.popupTitle;
            title.style.cssText = `
                margin: 0;
                font-size: 16px;
                font-weight: 600;
                color: #333;
            `;

            const closeButton = document.createElement('button');
            closeButton.innerHTML = '×';
            closeButton.style.cssText = `
                background: none;
                border: none;
                font-size: 24px;
                cursor: pointer;
                color: #666;
                padding: 0;
                width: 30px;
                height: 30px;
                display: flex;
                align-items: center;
                justify-content: center;
                border-radius: 4px;
                transition: background-color 0.2s;
            `;

            closeButton.addEventListener('mouseenter', function() {
                this.style.backgroundColor = '#e1e1e1';
            });
            closeButton.addEventListener('mouseleave', function() {
                this.style.backgroundColor = 'transparent';
            });

            header.appendChild(title);
            header.appendChild(closeButton);

            // Create iframe
            const iframe = document.createElement('iframe');
            iframe.src = `${config.baseUrl}/contracts/${sessionId}/iframe` + (config.noPreview ? '?no_preview=1' : '');
            iframe.style.cssText = `
                flex: 1;
                border: none;
                border-radius: 0 0 8px 8px;
                width: 100%;
            `;
            iframe.setAttribute('data-agp-session', sessionId);

            popupContent.appendChild(header);
            popupContent.appendChild(iframe);
            popup.appendChild(popupContent);

            // Set up message listener
            this._setupMessageListener(config, iframe);

            // Close popup handlers
            const closePopup = () => {
                if (popup.parentNode) {
                    popup.parentNode.removeChild(popup);
                }
                if (config.onClose) {
                    config.onClose();
                }
            };

            closeButton.addEventListener('click', closePopup);

            // Close on overlay click
            popup.addEventListener('click', function(e) {
                if (e.target === popup) {
                    closePopup();
                }
            });

            // Close on ESC key
            const handleKeyDown = (e) => {
                if (e.key === 'Escape') {
                    closePopup();
                    document.removeEventListener('keydown', handleKeyDown);
                }
            };
            document.addEventListener('keydown', handleKeyDown);

            document.body.appendChild(popup);

            return {
                popup: popup,
                iframe: iframe,
                close: closePopup,
                destroy: closePopup
            };
        },

        // Set up message listener
        _setupMessageListener: function (config, iframe) {
            const messageHandler = (event) => {
                console.log('AGP: Message received from AGP Iframe:', event.data, event.origin);
                
                // Origin validation - adjust this based on your security requirements
                if (event.origin !== window.location.origin && !event.origin.includes('localhost')) {
                    return;
                }
                
                console.log('AGP: Message received from AGP Iframe:', event.data);
                
                // Call custom message handler if provided
                if (config.onMessage && typeof config.onMessage === 'function') {
                    config.onMessage(event.data, event.origin, iframe);
                }
            };

            window.addEventListener('message', messageHandler);
            
            // Store reference to remove listener if needed
            iframe._agpMessageHandler = messageHandler;
        },

        // Utility method to destroy all AGP instances
        destroyAll: function() {
            // Remove all iframes
            const iframes = document.querySelectorAll('[data-agp-session]');
            iframes.forEach(iframe => {
                if (iframe._agpMessageHandler) {
                    window.removeEventListener('message', iframe._agpMessageHandler);
                }
                if (iframe.parentNode) {
                    iframe.parentNode.removeChild(iframe);
                }
            });

            // Remove all popups
            const popups = document.querySelectorAll('[data-agp-popup]');
            popups.forEach(popup => {
                if (popup.parentNode) {
                    popup.parentNode.removeChild(popup);
                }
            });
        }
    };
})();