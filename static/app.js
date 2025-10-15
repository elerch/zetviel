let currentQuery = 'tag:inbox';
let isLoading = false;

async function api(endpoint) {
    console.log('API call:', endpoint);
    const res = await fetch(`/api/${endpoint}`);
    console.log('Response status:', res.status);
    if (!res.ok) {
        const text = await res.text();
        console.error('API error response:', text);
        throw new Error(`API error: ${res.status}`);
    }
    const data = await res.json();
    console.log('API response:', data);
    return data;
}

function setStatus(state) {
    const status = document.getElementById('status');
    status.className = state === 'loading' ? 'status-loading' : state === 'ok' ? 'status-ok' : 'status-error';
}

function setLoading(loading) {
    isLoading = loading;
    const btn = document.querySelector('.search-bar button');
    btn.disabled = loading;
    btn.textContent = loading ? 'Loading...' : 'Search';
}

async function search() {
    if (isLoading) return;
    const query = document.getElementById('search').value;
    currentQuery = query;
    history.pushState({ query }, '', `/?q=${encodeURIComponent(query)}`);
    await loadThreads(query);
}

async function loadThreads(query) {
    setLoading(true);
    setStatus('loading');
    const list = document.getElementById('thread-list');

    try {
        const threads = await api(`query/${encodeURIComponent(query)}`);
        if (!threads || threads.length === 0) {
            list.innerHTML = '<div class="loading">No threads found</div>';
        } else {
            list.innerHTML = threads.map(t => `
                <div class="thread" onclick="loadThread('${t.thread_id}')">
                    <div class="thread-subject">${escapeHtml(t.subject)}</div>
                    <div class="thread-authors">${escapeHtml(t.authors)}</div>
                    <div class="thread-date">${new Date(t.newest_date * 1000).toLocaleString()}</div>
                </div>
            `).join('');
        }
        setStatus('ok');
    } catch (e) {
        console.error('Error in loadThreads:', e);
        list.innerHTML = `<div class="error">Error loading threads: ${escapeHtml(e.message)}</div>`;
        setStatus('error');
    } finally {
        setLoading(false);
    }
}

async function loadThread(threadId) {
    setStatus('loading');
    const view = document.getElementById('message-view');
    view.innerHTML = '<div class="loading">Loading messages...</div>';

    try {
        const messages = await api(`thread/${threadId}`);
        view.innerHTML = messages.map(m => `
            <div class="message">
                <div class="message-header">
                    <strong>From:</strong> ${escapeHtml(m.from || '')}<br>
                    <strong>To:</strong> ${escapeHtml(m.to || '')}<br>
                    <strong>Date:</strong> ${escapeHtml(m.date || '')}<br>
                    <strong>Subject:</strong> ${escapeHtml(m.subject || '')}
                </div>
                <button onclick="loadMessageContent('${m.message_id}')">Show Content</button>
                <div id="msg-${m.message_id}" class="message-content"></div>
            </div>
        `).join('');
        setStatus('ok');
    } catch (e) {
        console.error('Error in loadThread:', e);
        view.innerHTML = `<div class="error">Error loading thread: ${escapeHtml(e.message)}</div>`;
        setStatus('error');
    }
}

async function loadMessageContent(messageId) {
    setStatus('loading');
    const div = document.getElementById(`msg-${messageId}`);
    div.innerHTML = '<div class="loading">Loading content...</div>';

    try {
        const msg = await api(`message/${messageId}`);
        div.innerHTML = `
            <div class="content-type">${escapeHtml(msg.content_type)}</div>
            <div class="content">${msg.content_type === 'text/html' ? msg.content : `<pre>${escapeHtml(msg.content)}</pre>`}</div>
            ${msg.attachments.length ? `<div class="attachments">Attachments: ${msg.attachments.map(a => escapeHtml(a.filename)).join(', ')}</div>` : ''}
        `;
        setStatus('ok');
    } catch (e) {
        console.error('Error in loadMessageContent:', e);
        div.innerHTML = `<div class="error">Error loading message: ${escapeHtml(e.message)}</div>`;
        setStatus('error');
    }
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Initialize
window.addEventListener('DOMContentLoaded', () => {
    console.log('App initialized');
    const params = new URLSearchParams(location.search);
    const query = params.get('q') || 'tag:inbox';
    document.getElementById('search').value = query;
    loadThreads(query);

    // Allow Enter key to search
    document.getElementById('search').addEventListener('keypress', (e) => {
        if (e.key === 'Enter') search();
    });
});

window.addEventListener('popstate', (e) => {
    if (e.state?.query) {
        document.getElementById('search').value = e.state.query;
        loadThreads(e.state.query);
    }
});
