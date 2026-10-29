import React from 'react';
import { createRoot } from 'react-dom/client';
import { applyTokens, loadTheme, setTheme } from './tokens.js';
import App from './App.jsx';
import './style.css';

applyTokens();
setTheme(loadTheme());
createRoot(document.getElementById('root')).render(<App />);

// Keep the browser's install prompt so the "Tải ứng dụng" page can offer a real install button.
window.addEventListener('beforeinstallprompt', e => {
  e.preventDefault();
  window.__installPrompt = e;
  window.dispatchEvent(new Event('tt-installable'));
});
