/* 悬浮待办 · 跨平台前端逻辑 (Tauri v2 + 原生 JS) */

const TAURI = window.__TAURI__;
const appWindow = TAURI?.window?.getCurrentWindow?.();

async function openExternal(url) {
  try {
    if (TAURI?.opener?.openUrl) await TAURI.opener.openUrl(url);
    else await TAURI.core.invoke("plugin:opener|open_url", { url });
  } catch (e) {
    window.open(url, "_blank");
  }
}

/* ---------------- 数据模型 ---------------- */

const DAYS = ["today", "tomorrow", "dayAfterTomorrow"];
const DAY_TITLE = { today: "今天", tomorrow: "明天", dayAfterTomorrow: "后天" };
const STORAGE_KEY = "floating-todo/snapshot";

const uid = () =>
  crypto.randomUUID ? crypto.randomUUID() : String(Date.now() + Math.random());

function todayStr(d = new Date()) {
  const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  return `${x.getFullYear()}-${x.getMonth() + 1}-${x.getDate()}`;
}

function dayDelta(fromStr, toStr) {
  const [fy, fm, fd] = fromStr.split("-").map(Number);
  const [ty, tm, td] = toStr.split("-").map(Number);
  const a = new Date(fy, fm - 1, fd);
  const b = new Date(ty, tm - 1, td);
  return Math.round((b - a) / 86400000);
}

function dateLabel(offset) {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  return `${d.getMonth() + 1}月${d.getDate()}日`;
}

const pad = (n) => String(n).padStart(2, "0");
function yesterdayStr() {
  const d = new Date();
  d.setDate(d.getDate() - 1);
  return todayStr(d);
}
function nowHHMM() {
  const d = new Date();
  return pad(d.getHours()) + ":" + pad(d.getMinutes());
}

/* 从输入里解析时间，如 15:00 / 下午3点半 / 晚上8点30 / 9点 */
function parseTime(s) {
  let m = s.match(/(\d{1,2}):(\d{2})/);
  if (m) {
    return { time: pad(Math.min(23, +m[1])) + ":" + pad(Math.min(59, +m[2])), match: m[0] };
  }
  m = s.match(/(上午|早上|凌晨|下午|晚上|中午)?\s*(\d{1,2})\s*点\s*(半|\d{1,2})?\s*分?/);
  if (m && (m[1] || m[3] !== undefined || /点/.test(m[0]))) {
    let h = +m[2];
    let mm = 0;
    if (m[3] === "半") mm = 30;
    else if (m[3]) mm = Math.min(59, +m[3]);
    const p = m[1];
    if ((p === "下午" || p === "晚上") && h < 12) h += 12;
    if (p === "中午" && h < 12) h = 12;
    if ((p === "凌晨" || p === "早上" || p === "上午") && h === 12) h = 0;
    return { time: pad(Math.min(23, h)) + ":" + pad(mm), match: m[0] };
  }
  return null;
}

/* 自然语言：识别「明天/后天/今天」分组和时间，返回 {day, time, title} */
function parseQuickInput(text, defaultDay) {
  let title = text.trim();
  let day = defaultDay;
  if (/^(今天|今日)/.test(title)) { day = "today"; title = title.replace(/^(今天|今日)\s*/, ""); }
  else if (/^明天/.test(title)) { day = "tomorrow"; title = title.replace(/^明天\s*/, ""); }
  else if (/^后天/.test(title)) { day = "dayAfterTomorrow"; title = title.replace(/^后天\s*/, ""); }

  let time = null;
  const t = parseTime(title);
  if (t) { time = t.time; title = title.replace(t.match, " ").replace(/\s+/g, " ").trim(); }
  return { day, time, title: title.trim() };
}

function defaultState() {
  return {
    selectedDay: "today",
    itemsByDay: { today: [], tomorrow: [], dayAfterTomorrow: [] },
    recurringItems: [],
    settings: {
      alwaysOnTop: true,
      opacity: 0.78,
      appearance: "system",
      customBg: null,
      memoEnabled: false,
    },
    memo: { text: "", expanded: false },
    lastActiveDate: todayStr(),
  };
}

function load() {
  let s;
  try {
    s = JSON.parse(localStorage.getItem(STORAGE_KEY));
  } catch (e) {
    s = null;
  }
  const base = defaultState();
  if (!s) return base;
  // 合并，兼容旧数据缺字段
  const state = {
    ...base,
    ...s,
    itemsByDay: { ...base.itemsByDay, ...(s.itemsByDay || {}) },
    settings: { ...base.settings, ...(s.settings || {}) },
    memo: { ...base.memo, ...(s.memo || {}) },
    recurringItems: s.recurringItems || [],
    lastActiveDate: s.lastActiveDate || todayStr(),
  };
  return state;
}

let state = load();

function save() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

/* ---------------- 跨天滚动 ---------------- */

function rollOverIfNeeded() {
  const today = todayStr();
  const delta = dayDelta(state.lastActiveDate, today);
  if (delta <= 0) return;

  const offset = { today: 0, tomorrow: 1, dayAfterTomorrow: 2 };
  const result = { today: [], tomorrow: [], dayAfterTomorrow: [] };
  let overdue = [];

  for (const day of DAYS) {
    const items = state.itemsByDay[day] || [];
    const newOffset = offset[day] - delta;
    if (newOffset >= 0) {
      const target = DAYS.find((d) => offset[d] === newOffset);
      result[target].push(...items);
    } else {
      overdue.push(...items.filter((it) => !it.completed));
    }
  }
  // 过期未完成顺延到今天底部
  result.today = [...result.today, ...overdue];
  // 新的一天，今天的待办重置提醒标记
  result.today = result.today.map((it) => ({ ...it, notified: false }));

  // 常驻待办每天重置完成状态与提醒；中断超过一天则连胜清零
  const y = yesterdayStr();
  state.recurringItems = state.recurringItems.map((it) => {
    const reset = { ...it, completed: false, notified: false };
    if (it.lastDone !== y && it.lastDone !== today) reset.streak = 0;
    return reset;
  });

  state.itemsByDay = result;
  state.lastActiveDate = today;
  save();
}

/* ---------------- 业务操作 ---------------- */

const stableSort = (arr) => [
  ...arr.filter((i) => !i.completed),
  ...arr.filter((i) => i.completed),
];

function items(day = state.selectedDay) {
  return state.itemsByDay[day] || [];
}
function incompleteCount(day = state.selectedDay) {
  return items(day).filter((i) => !i.completed).length;
}
function completedCount(day = state.selectedDay) {
  return items(day).filter((i) => i.completed).length;
}

function addItem(title, day = state.selectedDay, time = null) {
  const t = title.trim();
  if (!t) return null;
  const it = { id: uid(), title: t, detail: "", time, completed: false, notified: false, createdAt: Date.now() };
  state.itemsByDay[day].unshift(it);
  save();
  return it;
}
function toggleItem(id, day) {
  const arr = state.itemsByDay[day];
  const it = arr.find((i) => i.id === id);
  if (!it) return;
  it.completed = !it.completed;
  state.itemsByDay[day] = stableSort(arr);
  save();
}
function deleteItem(id, day) {
  state.itemsByDay[day] = state.itemsByDay[day].filter((i) => i.id !== id);
  save();
}
function updateItem(id, day, title, detail) {
  const it = state.itemsByDay[day].find((i) => i.id === id);
  if (!it) return;
  if (title !== undefined && title.trim()) it.title = title.trim();
  if (detail !== undefined) it.detail = detail.trim();
  save();
}
function moveItem(id, from, to) {
  const arr = state.itemsByDay[from];
  const idx = arr.findIndex((i) => i.id === id);
  if (idx < 0) return;
  const [it] = arr.splice(idx, 1);
  state.itemsByDay[to].unshift(it);
  save();
}
function clearCompleted(day) {
  state.itemsByDay[day] = state.itemsByDay[day].filter((i) => !i.completed);
  save();
}

/* 常驻「每天」待办 */
function addRecurring(title, time = null) {
  const t = title.trim();
  if (!t) return;
  state.recurringItems.unshift({
    id: uid(),
    title: t,
    detail: "",
    time,
    completed: false,
    notified: false,
    streak: 0,
    lastDone: null,
    createdAt: Date.now(),
  });
  save();
}
function toggleRecurring(id) {
  const it = state.recurringItems.find((i) => i.id === id);
  if (!it) return;
  const today = todayStr();
  if (!it.completed) {
    it.completed = true;
    it.notified = true;
    if (it.lastDone === today) {
      // 今天已计入连胜
    } else if (it.lastDone === yesterdayStr()) {
      it.streak = (it.streak || 0) + 1;
    } else {
      it.streak = 1;
    }
    it.lastDone = today;
  } else {
    it.completed = false;
    if (it.lastDone === today) {
      it.streak = Math.max(0, (it.streak || 0) - 1);
      it.lastDone = it.streak > 0 ? yesterdayStr() : null;
    }
  }
  state.recurringItems = stableSort(state.recurringItems);
  save();
}
function deleteRecurring(id) {
  state.recurringItems = state.recurringItems.filter((i) => i.id !== id);
  save();
}
function updateRecurringTitle(id, title) {
  const it = state.recurringItems.find((i) => i.id === id);
  if (it && title.trim()) it.title = title.trim();
  save();
}
function pinAsRecurring(id, from) {
  const arr = state.itemsByDay[from];
  const idx = arr.findIndex((i) => i.id === id);
  if (idx < 0) return;
  const [it] = arr.splice(idx, 1);
  it.completed = false;
  state.recurringItems.unshift(it);
  save();
}
function unpinRecurring(id) {
  const idx = state.recurringItems.findIndex((i) => i.id === id);
  if (idx < 0) return;
  const [it] = state.recurringItems.splice(idx, 1);
  state.itemsByDay.today.unshift(it);
  save();
}

/* ---------------- 工具 ---------------- */

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
  );
}
function linkify(s) {
  const escaped = esc(s);
  return escaped.replace(
    /(https?:\/\/[^\s<]+)/g,
    '<a data-link="$1">$1</a>'
  );
}

const ICONS = {
  gear: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>',
  check: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="3"><polyline points="20 6 9 17 4 12"/></svg>',
  dots: '<svg viewBox="0 0 24 24" width="15" height="15" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
  trash: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>',
  plus: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>',
  send: '<svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor"><path d="M12 2 4.5 20l7.5-3.5L19.5 20z" transform="rotate(0 12 12)"/></svg>',
  arrowUp: '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="8 12 12 8 16 12"/><line x1="12" y1="8" x2="12" y2="16"/></svg>',
  x: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>',
  repeat: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2"><polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/></svg>',
  note: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>',
  pencil: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/></svg>',
  expand: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/><line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/></svg>',
  chevron: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 12 15 18 9"/></svg>',
  pinOff: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2"><line x1="2" y1="2" x2="22" y2="22"/><path d="M12 17v5"/><path d="M9 9v1.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h11"/><path d="M15 9.34V6h1a2 2 0 0 0 0-4H7.89"/></svg>',
  arrowRight: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></svg>',
  clock: '<svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" stroke-width="2" style="vertical-align:-1px;margin-right:2px"><circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 15 14"/></svg>',
  download: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>',
  upload: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>',
};

/* ---------------- 渲染 ---------------- */

const app = document.getElementById("app");
let compact = false;
let activeMenu = null; // { id, day, kind }

function applyWindowChrome() {
  const root = document.documentElement;
  root.dataset.theme = state.settings.appearance;
  root.style.setProperty("--opacity", state.settings.opacity);
  if (state.settings.customBg) {
    root.style.setProperty("--panel-top", state.settings.customBg);
    root.style.setProperty("--panel-bottom", state.settings.customBg);
  } else {
    root.style.removeProperty("--panel-top");
    root.style.removeProperty("--panel-bottom");
  }
  if (appWindow) appWindow.setAlwaysOnTop(!!state.settings.alwaysOnTop).catch(() => {});
}

function rowHtml(it, day, kind) {
  const badge = kind === "recurring" && compact ? `<span class="badge">${ICONS.repeat}</span>` : "";
  const detail =
    !compact && it.detail
      ? `<div class="detail">${linkify(it.detail)}</div>`
      : "";
  let actions = "";
  if (!compact) {
    if (kind === "recurring") {
      actions = `<div class="actions">
        <button class="icon-btn sm" data-act="unpin" data-id="${it.id}" title="取消每天">${ICONS.pinOff}</button>
        <button class="icon-btn sm" data-act="rdel" data-id="${it.id}" title="删除">${ICONS.trash}</button>
      </div>`;
    } else {
      actions = `<div class="actions">
        <button class="icon-btn sm" data-act="menu" data-id="${it.id}" data-day="${day}" title="更多">${ICONS.dots}</button>
        <button class="icon-btn sm" data-act="del" data-id="${it.id}" data-day="${day}" title="删除">${ICONS.trash}</button>
      </div>`;
    }
  }
  const editAct = kind === "recurring" ? "redit" : "edit";
  const timeChip = it.time ? `<span class="time-chip">${ICONS.clock}${it.time}</span>` : "";
  const streakChip =
    kind === "recurring" && it.streak > 0
      ? `<span class="streak-chip" title="已连续 ${it.streak} 天">🔥${it.streak}</span>`
      : "";
  return `<div class="row ${it.completed ? "done" : ""}" data-row="${it.id}">
    <div class="check ${it.completed ? "on" : ""}" data-act="${kind === "recurring" ? "rtoggle" : "toggle"}" data-id="${it.id}" data-day="${day}">${it.completed ? ICONS.check : ""}</div>
    <div class="body" data-act="${editAct}" data-id="${it.id}" data-day="${day}">
      <div class="title">${esc(it.title)}${timeChip}${streakChip}</div>
      ${detail}
    </div>
    ${badge}${actions}
  </div>`;
}

function render() {
  rollOverIfNeeded();
  applyWindowChrome();

  const day = compact ? "today" : state.selectedDay;
  const showRecurring = day === "today" && state.recurringItems.length > 0;
  const cnt = incompleteCount();

  let html = "";

  if (!compact) {
    const sub =
      cnt === 0 ? "这一页已经清空" : `${DAY_TITLE[state.selectedDay]}还有 ${cnt} 件事`;
    html += `<div class="header">
      <div class="titles"><h1>悬浮待办</h1><p>${sub}</p></div>
      <div class="spacer"></div>
      <div class="count-pill ${cnt === 0 ? "zero" : ""}">${cnt}</div>
      <button class="icon-btn" data-act="settings" title="设置">${ICONS.gear}</button>
    </div>`;

    html += `<div class="day-picker">`;
    DAYS.forEach((d, i) => {
      html += `<div class="day-seg ${state.selectedDay === d ? "sel" : ""}" data-act="day" data-day="${d}">
        <span class="t">${DAY_TITLE[d]}</span><span class="d">${dateLabel(i)}</span>
      </div>`;
    });
    html += `</div>`;
  }

  if (showRecurring) {
    html += `<div class="recurring"><div class="head">
      <span class="ic">${ICONS.repeat}</span><span>每天</span><div class="spacer"></div>`;
    if (!compact)
      html += `<button class="icon-btn sm" data-act="raddtoggle" title="添加每天常驻待办">${ICONS.plus}</button>`;
    html += `</div>`;
    state.recurringItems.forEach((it) => (html += rowHtml(it, "today", "recurring")));
    if (!compact && recurringComposerOpen) {
      html += `<div class="composer sm"><span class="ic">${ICONS.repeat}</span>
        <input id="recur-input" placeholder="添加每天常驻待办" value="${esc(recurDraft)}"/>
        <button class="send" data-act="raddsubmit">${ICONS.arrowUp}</button></div>`;
    }
    html += `</div>`;
  }

  // 列表
  const list = items(day);
  if (list.length === 0) {
    const a = showRecurring ? `${DAY_TITLE[day]}没有临时待办` : `${DAY_TITLE[day]}还没有待办`;
    const b = showRecurring ? "上方是每天常驻的事" : "写下一件真正要推进的事";
    html += `<div class="empty"><div class="ic">${ICONS.note}</div><div class="a">${a}</div><div class="b">${b}</div></div>`;
  } else {
    html += `<div class="list">`;
    list.forEach((it) => (html += rowHtml(it, day, "normal")));
    html += `</div>`;
  }

  if (!compact) {
    if (completedCount(day) > 0) {
      html += `<div class="clear-bar"><button data-act="clear" data-day="${day}">${ICONS.trash}<span>清除已完成（${completedCount(day)}）</span></button></div>`;
    }
    // 输入框
    const editing = composerEditId;
    html += `<div class="composer">
      <span class="ic">${editing ? ICONS.pencil : ICONS.plus}</span>
      <input id="main-input" placeholder="${editing ? "编辑待办标题" : "添加" + DAY_TITLE[state.selectedDay] + "待办"}" value="${esc(draft)}"/>
      ${editing ? `<button class="icon-btn sm" data-act="canceledit">${ICONS.x}</button>` : ""}
      <button class="send ${draft.trim() ? "" : "off"}" data-act="submit">${editing ? ICONS.arrowUp : ICONS.arrowUp}</button>
    </div>`;

    // 备忘录
    if (state.settings.memoEnabled) {
      html += `<div class="memo"><div class="head" data-act="memotoggle">
        <span class="ic">${ICONS.note}</span><span>全局备忘录</span><div class="spacer"></div>
        <span style="transform:rotate(${state.memo.expanded ? 180 : 0}deg);transition:.2s">${ICONS.chevron}</span></div>`;
      if (state.memo.expanded) {
        html += `<textarea id="memo-input" placeholder="记录临时想法、链接、会议号">${esc(state.memo.text)}</textarea>`;
      }
      html += `</div>`;
    }
  }

  // 紧凑模式放大按钮
  if (compact) {
    html += `<button class="icon-btn expand-btn" data-act="expand" title="放大">${ICONS.expand}</button>`;
  }

  app.innerHTML = html;

  // 头部可拖动
  const header = app.querySelector(".header");
  if (header) header.addEventListener("mousedown", onDragStart);

  // 保持输入焦点
  if (focusMain) {
    const mi = document.getElementById("main-input");
    if (mi) { mi.focus(); mi.setSelectionRange(mi.value.length, mi.value.length); }
    focusMain = false;
  }
  if (focusRecur) {
    const ri = document.getElementById("recur-input");
    if (ri) ri.focus();
    focusRecur = false;
  }
}

/* ---------------- 交互状态 ---------------- */

let draft = "";
let composerEditId = null;
let composerEditDay = null;
let recurDraft = "";
let recurringComposerOpen = false;
let recurEditId = null;
let focusMain = false;
let focusRecur = false;

function onDragStart(e) {
  if (e.target.closest("button")) return;
  appWindow?.startDragging().catch(() => {});
}

/* 事件委托 */
app.addEventListener("click", (e) => {
  const link = e.target.closest("a[data-link]");
  if (link) { e.preventDefault(); openExternal(link.dataset.link); return; }

  const el = e.target.closest("[data-act]");
  if (!el) return;
  const act = el.dataset.act;
  const id = el.dataset.id;
  const day = el.dataset.day;

  switch (act) {
    case "day": state.selectedDay = day; save(); render(); break;
    case "toggle": {
      const wasOpen = !state.itemsByDay[day].find((i) => i.id === id)?.completed;
      toggleItem(id, day);
      if (wasOpen) celebrate(el);
      render();
      break;
    }
    case "rtoggle": {
      const wasOpen = !state.recurringItems.find((i) => i.id === id)?.completed;
      toggleRecurring(id);
      if (wasOpen) celebrate(el);
      render();
      break;
    }
    case "del": deleteItem(id, day); render(); break;
    case "rdel": deleteRecurring(id); render(); break;
    case "unpin": unpinRecurring(id); render(); break;
    case "clear": clearCompleted(day); render(); break;
    case "edit": startEdit(id, day); break;
    case "redit": startRecurEdit(id); break;
    case "submit": commitMain(); break;
    case "canceledit": cancelEdit(); break;
    case "raddtoggle": recurringComposerOpen = !recurringComposerOpen; focusRecur = recurringComposerOpen; render(); break;
    case "raddsubmit": commitRecur(); break;
    case "expand": expandWindow(); break;
    case "settings": openSettings(); break;
    case "memotoggle": state.memo.expanded = !state.memo.expanded; save(); render(); break;
    case "menu": openRowMenu(id, day, el); break;
  }
});

/* 输入框事件（委托 input/keydown） */
app.addEventListener("input", (e) => {
  if (e.target.id === "main-input") {
    draft = e.target.value;
    const send = app.querySelector('[data-act="submit"]');
    if (send) send.classList.toggle("off", !draft.trim());
  } else if (e.target.id === "recur-input") {
    recurDraft = e.target.value;
  } else if (e.target.id === "memo-input") {
    state.memo.text = e.target.value;
    save();
  }
});
app.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    if (e.target.id === "main-input") { e.preventDefault(); commitMain(); }
    else if (e.target.id === "recur-input") { e.preventDefault(); commitRecur(); }
  }
  if (e.key === "Escape" && e.target.id === "main-input") {
    if (composerEditId) cancelEdit();
    else { draft = ""; appWindow?.hide().catch(() => {}); }
  }
});

function commitMain() {
  const t = draft.trim();
  if (!t) return;
  if (composerEditId) {
    updateItem(composerEditId, composerEditDay, t, undefined);
    composerEditId = null; composerEditDay = null;
  } else {
    const { day, time, title } = parseQuickInput(t, state.selectedDay);
    if (!title) return;
    addItem(title, day, time);
    if (day !== state.selectedDay) state.selectedDay = day;
  }
  draft = ""; focusMain = true; render();
}
function startEdit(id, day) {
  const it = state.itemsByDay[day].find((i) => i.id === id);
  if (!it) return;
  state.selectedDay = day;
  composerEditId = id; composerEditDay = day; draft = it.title; focusMain = true;
  render();
}
function cancelEdit() {
  composerEditId = null; composerEditDay = null; draft = ""; focusMain = true; render();
}
function commitRecur() {
  const t = recurDraft.trim();
  if (!t) return;
  if (recurEditId) { updateRecurringTitle(recurEditId, t); recurEditId = null; }
  else {
    const parsed = parseTime(t);
    const time = parsed ? parsed.time : null;
    const title = parsed ? t.replace(parsed.match, " ").replace(/\s+/g, " ").trim() : t;
    if (title) addRecurring(title, time);
  }
  recurDraft = ""; focusRecur = true; render();
}
function startRecurEdit(id) {
  const it = state.recurringItems.find((i) => i.id === id);
  if (!it) return;
  recurringComposerOpen = true; recurEditId = id; recurDraft = it.title; focusRecur = true;
  render();
}

/* ---------------- 行浮层菜单 ---------------- */

function closeMenu() {
  document.querySelector(".menu")?.remove();
  document.querySelector(".menu-mask")?.remove();
}
function openRowMenu(id, day, anchorEl) {
  closeMenu();
  const it = state.itemsByDay[day].find((i) => i.id === id);
  if (!it) return;
  const others = DAYS.filter((d) => d !== day);
  const mask = document.createElement("div");
  mask.className = "menu-mask";
  mask.style.cssText = "position:absolute;inset:0;z-index:55";
  mask.addEventListener("click", closeMenu);
  document.body.appendChild(mask);

  const menu = document.createElement("div");
  menu.className = "menu";
  menu.innerHTML =
    `<button data-m="edit">${ICONS.pencil}<span>编辑</span></button>` +
    `<button data-m="detail">${ICONS.note}<span>${it.detail ? "编辑描述" : "添加描述"}</span></button>` +
    `<button data-m="pin">${ICONS.repeat}<span>设为每天</span></button>` +
    `<div class="sep"></div>` +
    others.map((d) => `<button data-m="move:${d}">${ICONS.arrowRight}<span>移到${DAY_TITLE[d]}</span></button>`).join("") +
    `<div class="sep"></div>` +
    `<button class="danger" data-m="del">${ICONS.trash}<span>删除</span></button>`;
  document.body.appendChild(menu);

  const r = anchorEl.getBoundingClientRect();
  const mw = 160, mh = menu.offsetHeight;
  let left = Math.min(r.right - mw, window.innerWidth - mw - 8);
  left = Math.max(8, left);
  let top = r.bottom + 6;
  if (top + mh > window.innerHeight - 8) top = r.top - mh - 6;
  menu.style.left = left + "px";
  menu.style.top = top + "px";

  menu.addEventListener("click", (e) => {
    const b = e.target.closest("[data-m]");
    if (!b) return;
    const m = b.dataset.m;
    closeMenu();
    if (m === "edit") startEdit(id, day);
    else if (m === "detail") openDetailEditor(id, day);
    else if (m === "pin") { pinAsRecurring(id, day); render(); }
    else if (m === "del") { deleteItem(id, day); render(); }
    else if (m.startsWith("move:")) { moveItem(id, day, m.slice(5)); render(); }
  });
}

/* 描述编辑弹窗 */
function openDetailEditor(id, day) {
  const it = state.itemsByDay[day].find((i) => i.id === id);
  if (!it) return;
  const overlay = document.createElement("div");
  overlay.className = "overlay";
  overlay.innerHTML = `<div class="settings" style="margin-top:40px;gap:12px">
    <h2>${DAY_TITLE[day]}待办详情</h2>
    <div><div style="font-size:11px;color:var(--text-secondary);margin-bottom:5px">标题</div>
    <div class="composer sm"><input id="de-title" value="${esc(it.title)}"/></div></div>
    <div><div style="font-size:11px;color:var(--text-secondary);margin-bottom:5px">描述</div>
    <div class="memo"><textarea id="de-detail" style="border-top:none">${esc(it.detail)}</textarea></div></div>
    <div class="set-row"><button class="link-btn" data-de="cancel">取消</button>
    <button class="link-btn" style="color:var(--accent);font-weight:600" data-de="save">保存详情</button></div>
  </div>`;
  document.body.appendChild(overlay);
  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) overlay.remove();
    const b = e.target.closest("[data-de]");
    if (!b) return;
    if (b.dataset.de === "cancel") overlay.remove();
    else {
      updateItem(id, day, overlay.querySelector("#de-title").value, overlay.querySelector("#de-detail").value);
      overlay.remove();
      render();
    }
  });
  overlay.querySelector("#de-title")?.focus();
}

/* ---------------- 设置面板 ---------------- */

function openSettings() {
  const overlay = document.createElement("div");
  overlay.className = "overlay";
  const s = state.settings;
  const bgHex = s.customBg ? rgbToHex(s.customBg) : "#dceaff";
  overlay.innerHTML = `<div class="settings">
    <h2>小组件设置</h2>
    <div class="set-row"><span>始终置顶</span><div class="switch ${s.alwaysOnTop ? "on" : ""}" data-s="alwaysOnTop"></div></div>
    <div class="set-row"><span>开机自启动</span><div class="switch" id="autostart-sw" data-s="autostart"></div></div>
    <div class="set-row"><span>开启备忘录</span><div class="switch ${s.memoEnabled ? "on" : ""}" data-s="memoEnabled"></div></div>
    <div>
      <div style="font-size:13px;font-weight:500;margin-bottom:6px">外观</div>
      <div class="seg-control">
        <button class="${s.appearance === "system" ? "on" : ""}" data-ap="system">跟随系统</button>
        <button class="${s.appearance === "light" ? "on" : ""}" data-ap="light">浅色</button>
        <button class="${s.appearance === "dark" ? "on" : ""}" data-ap="dark">深色</button>
      </div>
    </div>
    <div class="set-row"><span>背景色</span>
      <div style="display:flex;align-items:center;gap:8px">
        <input type="color" id="bg-color" value="${bgHex}"/>
        <button class="link-btn" data-s="resetBg" ${s.customBg ? "" : 'style="opacity:.45"'}>恢复默认</button>
      </div>
    </div>
    <div>
      <div class="set-row"><span>透明度</span><span style="color:var(--text-secondary)">${Math.round(s.opacity * 100)}%</span></div>
      <input type="range" id="op-range" min="0.2" max="0.95" step="0.01" value="${s.opacity}"/>
    </div>
    <div class="set-row" style="gap:8px">
      <button class="data-btn" data-s="export">${ICONS.download}<span>导出备份</span></button>
      <button class="data-btn" data-s="import">${ICONS.upload}<span>导入备份</span></button>
    </div>
    <div style="font-size:11px;color:var(--text-secondary);line-height:1.6">
      💡 全局快捷键 <b>${navigator.platform.includes("Mac") ? "⌘⇧Space" : "Ctrl+Shift+Space"}</b> 可在任意应用中唤起并聚焦输入框，快速记一笔。<br>
      ⏰ 输入「明天 15:00 开会」会自动识别日期与提醒时间。
    </div>
    <div class="set-row" style="justify-content:flex-end"><button class="link-btn" data-s="close">完成</button></div>
  </div>`;
  document.body.appendChild(overlay);

  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) { overlay.remove(); return; }
    const sw = e.target.closest("[data-s]");
    if (sw) {
      const key = sw.dataset.s;
      if (key === "alwaysOnTop") { state.settings.alwaysOnTop = !state.settings.alwaysOnTop; sw.classList.toggle("on"); }
      else if (key === "memoEnabled") {
        state.settings.memoEnabled = !state.settings.memoEnabled;
        if (state.settings.memoEnabled) state.memo.expanded = true;
        sw.classList.toggle("on");
      }
      else if (key === "resetBg") { state.settings.customBg = null; overlay.remove(); save(); render(); openSettings(); return; }
      else if (key === "autostart") { toggleAutostart(sw); return; }
      else if (key === "export") { exportBackup(); return; }
      else if (key === "import") { importBackup(overlay); return; }
      else if (key === "close") { overlay.remove(); }
      save(); applyWindowChrome(); render();
    }
    const ap = e.target.closest("[data-ap]");
    if (ap) {
      state.settings.appearance = ap.dataset.ap;
      overlay.querySelectorAll("[data-ap]").forEach((b) => b.classList.toggle("on", b === ap));
      save(); applyWindowChrome();
    }
  });
  overlay.querySelector("#op-range").addEventListener("input", (e) => {
    state.settings.opacity = parseFloat(e.target.value);
    e.target.previousElementSibling.querySelector("span:last-child").textContent = Math.round(state.settings.opacity * 100) + "%";
    applyWindowChrome(); save();
  });
  overlay.querySelector("#bg-color").addEventListener("input", (e) => {
    state.settings.customBg = hexToRgb(e.target.value);
    applyWindowChrome(); save();
  });
  // 异步同步开机自启动开关的真实状态
  (async () => {
    try {
      const on = await TAURI?.autostart?.isEnabled();
      overlay.querySelector("#autostart-sw")?.classList.toggle("on", !!on);
    } catch (e) {}
  })();
}

async function toggleAutostart(sw) {
  try {
    const on = await TAURI.autostart.isEnabled();
    if (on) await TAURI.autostart.disable();
    else await TAURI.autostart.enable();
    sw.classList.toggle("on", !on);
  } catch (e) {}
}

async function exportBackup() {
  try {
    await TAURI.core.invoke("export_data", { json: JSON.stringify(state, null, 2) });
  } catch (e) {}
}

async function importBackup(overlay) {
  try {
    const content = await TAURI.core.invoke("import_data");
    if (!content) return;
    const parsed = JSON.parse(content);
    if (!parsed || !parsed.itemsByDay) return;
    const base = defaultState();
    state = {
      ...base,
      ...parsed,
      itemsByDay: { ...base.itemsByDay, ...(parsed.itemsByDay || {}) },
      settings: { ...base.settings, ...(parsed.settings || {}) },
      memo: { ...base.memo, ...(parsed.memo || {}) },
      recurringItems: parsed.recurringItems || [],
    };
    save();
    overlay?.remove();
    applyWindowChrome();
    render();
  } catch (e) {}
}

function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return `${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}`;
}
function rgbToHex(rgb) {
  const [r, g, b] = rgb.split(",").map((x) => parseInt(x.trim()));
  return "#" + [r, g, b].map((x) => x.toString(16).padStart(2, "0")).join("");
}

/* ---------------- 完成撒花 ---------------- */

const CONFETTI_COLORS = ["#1573ff", "#29ab56", "#ffb020", "#ff5d8f", "#7c5cff"];
function celebrate(anchorEl) {
  const r = anchorEl.getBoundingClientRect();
  const cx = r.left + r.width / 2;
  const cy = r.top + r.height / 2;
  for (let i = 0; i < 14; i++) {
    const p = document.createElement("div");
    p.className = "confetti";
    p.style.background = CONFETTI_COLORS[i % CONFETTI_COLORS.length];
    p.style.left = cx + "px";
    p.style.top = cy + "px";
    const ang = (Math.PI * 2 * i) / 14 + Math.random() * 0.6;
    const dist = 26 + Math.random() * 30;
    p.style.setProperty("--dx", Math.cos(ang) * dist + "px");
    p.style.setProperty("--dy", (Math.sin(ang) * dist - 18) + "px");
    document.body.appendChild(p);
    setTimeout(() => p.remove(), 700);
  }
}

/* ---------------- 提醒通知 ---------------- */

async function ensureNotifyPermission() {
  try {
    const n = TAURI?.notification;
    if (!n) return false;
    let granted = await n.isPermissionGranted();
    if (!granted) granted = (await n.requestPermission()) === "granted";
    return granted;
  } catch (e) {
    return false;
  }
}

async function checkReminders() {
  const now = nowHHMM();
  const due = [];
  let changed = false;
  const scan = (it) => {
    if (it.time && !it.completed && !it.notified && it.time <= now) {
      it.notified = true;
      due.push(it);
      changed = true;
    }
  };
  state.itemsByDay.today.forEach(scan);
  state.recurringItems.forEach(scan);
  if (changed) save();
  if (due.length) {
    const ok = await ensureNotifyPermission();
    if (ok) {
      due.forEach((it) =>
        TAURI.notification.sendNotification({
          title: "悬浮待办 · 到点提醒",
          body: `${it.time}　${it.title}`,
        })
      );
    }
  }
}

/* ---------------- 窗口尺寸 / 缩放 ---------------- */

function expandWindow() {
  if (!appWindow || !TAURI?.window?.LogicalSize) return;
  appWindow.setSize(new TAURI.window.LogicalSize(340, 560)).catch(() => {});
}

document.querySelectorAll(".resize").forEach((h) => {
  h.addEventListener("mousedown", (e) => {
    e.preventDefault();
    appWindow?.startResizeDragging(h.dataset.dir).catch(() => {});
  });
});

function updateCompact() {
  const w = window.innerWidth, hh = window.innerHeight;
  const c = w < 300 || hh < 280;
  if (c !== compact) { compact = c; document.documentElement.classList.toggle("compact", c); render(); }
  else { document.documentElement.classList.toggle("compact", c); }
}
window.addEventListener("resize", updateCompact);

/* ---------------- 全局快捷键：快速捕获 ---------------- */

TAURI?.event?.listen?.("quick-capture", () => {
  closeMenu();
  document.querySelector(".overlay")?.remove();
  if (compact) expandWindow();
  focusMain = true;
  render();
  setTimeout(() => {
    const mi = document.getElementById("main-input");
    if (mi) { mi.focus(); mi.select(); }
  }, 60);
});

/* ---------------- 启动 ---------------- */

updateCompact();
render();
applyWindowChrome();

// 跨午夜定期滚动 + 到点提醒
setInterval(() => render(), 5 * 60 * 1000);
setInterval(checkReminders, 30 * 1000);
checkReminders();
