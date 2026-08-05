import React from 'react';
import ReactDOM from 'react-dom/client';
import { library } from '@fortawesome/fontawesome-svg-core';
import { fas } from '@fortawesome/free-solid-svg-icons';
import './index.css';
import App from './components/App';
import { isEnvBrowser } from './utils/misc';

library.add(fas);

// Outside CEF there is no game behind the page, so stand in a screenshot to
// make the transparent panels readable while developing.
if (isEnvBrowser()) {
    const root = document.getElementById('root')!;
    root.style.backgroundImage = 'url("https://i.imgur.com/3pzRj9n.png")';
    root.style.backgroundSize = 'cover';
    root.style.backgroundRepeat = 'no-repeat';
    root.style.backgroundPosition = 'center';
    root.style.userSelect = 'none';
}

ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
        <App />
    </React.StrictMode>
);
