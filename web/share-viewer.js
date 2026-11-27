(function () {
  var API_BASE =
    window.CDT_SHARE_API_BASE ||
    (typeof window.cdtShareApiBase === 'function'
      ? window.cdtShareApiBase()
      : 'https://api-cdt.junpgle.me');
  var root = document.getElementById('share-root');
  if (!root) return;

  var state = {
    code: window.cdtShareCode || '',
    token: null,
    loading: true,
    loadingHistory: false,
    includeHistory: false,
    needsPassword: false,
    verifying: false,
    error: '',
    passwordError: '',
    data: null,
    joinOpen: false,
    joinSubmitting: false,
    joinError: ''
  };

  function esc(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function showToast(msg) {
    var existing = document.querySelector('.cdt-toast');
    if (existing) existing.remove();
    var el = document.createElement('div');
    el.className = 'cdt-toast';
    el.textContent = msg;
    document.body.appendChild(el);
    window.setTimeout(function () {
      if (el.parentNode) el.remove();
    }, 2600);
  }

  function pad2(n) {
    return n < 10 ? '0' + n : String(n);
  }

  function formatDate(ms) {
    if (!ms) return '';
    var d = new Date(Number(ms));
    if (isNaN(d.getTime())) return '';
    return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
  }

  function formatDateTime(ms, isAllDay) {
    if (!ms) return '';
    var d = new Date(Number(ms));
    if (isNaN(d.getTime())) return '';
    var datePart = d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
    if (isAllDay) return datePart + ' 全天';
    return datePart + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  }

  function formatCountdownRemaining(targetMs, isCompleted) {
    if (isCompleted) return { text: '已完成', cls: 'success' };
    var now = new Date();
    var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    var target = new Date(Number(targetMs));
    if (isNaN(target.getTime())) return { text: '', cls: '' };
    var startOfTarget = new Date(target.getFullYear(), target.getMonth(), target.getDate()).getTime();
    var diffDays = Math.round((startOfTarget - startOfToday) / 86400000);
    if (diffDays > 0) return { text: '还有 ' + diffDays + ' 天', cls: '' };
    if (diffDays === 0) return { text: '就是今天', cls: 'warn' };
    return { text: '已过去 ' + Math.abs(diffDays) + ' 天', cls: 'danger' };
  }

  function parseScheduleList(data) {
    var raw = data.schedules || data.fixed_schedules || data.fixedSchedules || [];
    if (!Array.isArray(raw)) return [];
    return raw.filter(function (item) {
      return item && !item.is_deleted && item.is_deleted !== 1;
    });
  }

  function isScheduleEnded(item, nowMs) {
    var status = item.status;
    if (status === 2 || status === 'ended' || status === 'cancelled' || status === 3) {
      return true;
    }
    var endMs = Number(item.end_time || item.endTime || 0);
    if (endMs > 0) return endMs < nowMs;
    var startMs = Number(item.start_time || item.startTime || 0);
    if (startMs > 0) return startMs < nowMs;
    if (item.date) {
      var d = new Date(item.date);
      if (!isNaN(d.getTime())) {
        d.setHours(23, 59, 59, 999);
        return d.getTime() < nowMs;
      }
    }
    return false;
  }

  function formatScheduleTime(item) {
    var dateStr = item.date ? String(item.date).slice(0, 10) : '';
    var startMs = Number(item.start_time || item.startTime || 0);
    var endMs = Number(item.end_time || item.endTime || 0);
    if (!dateStr && startMs > 0) {
      dateStr = formatDate(startMs);
    }
    var timeRange = '';
    if (startMs > 0) {
      var s = new Date(startMs);
      timeRange = pad2(s.getHours()) + ':' + pad2(s.getMinutes());
      if (endMs > 0) {
        var e = new Date(endMs);
        timeRange += ' - ' + pad2(e.getHours()) + ':' + pad2(e.getMinutes());
      }
    }
    return [dateStr, timeRange].filter(Boolean).join(' ');
  }

  function renderLoading() {
    root.innerHTML =
      '<div class="cdt-center-box">' +
      '  <div class="cdt-card cdt-auth-card">' +
      '    <div class="cdt-spinner"></div>' +
      '    <h2>正在加载团队分享</h2>' +
      '    <p>已启用按需轻量加载，无需等待完整应用资源</p>' +
      '  </div>' +
      '</div>';
  }

  function renderError() {
    root.innerHTML =
      '<div class="cdt-center-box">' +
      '  <div class="cdt-card cdt-auth-card">' +
      '    <div class="cdt-auth-icon">!</div>' +
      '    <h2>无法打开分享</h2>' +
      '    <p>' + esc(state.error || '加载失败，请稍后重试') + '</p>' +
      '    <div style="margin-top:20px;display:flex;flex-direction:column;gap:10px;">' +
      '      <button class="cdt-btn" id="cdt-retry-btn" type="button">重新加载</button>' +
      (window.cdtOpenFullApp
        ? '      <button class="cdt-btn cdt-btn-secondary" id="cdt-full-app-btn" type="button">打开完整版网页 App</button>'
        : '') +
      '    </div>' +
      '  </div>' +
      '</div>';
    var retryBtn = document.getElementById('cdt-retry-btn');
    if (retryBtn) {
      retryBtn.addEventListener('click', function () {
        loadData({ forceNetwork: true });
      });
    }
    var fullBtn = document.getElementById('cdt-full-app-btn');
    if (fullBtn && window.cdtOpenFullApp) {
      fullBtn.addEventListener('click', window.cdtOpenFullApp);
    }
  }

  function renderPassword() {
    root.innerHTML =
      '<div class="cdt-center-box">' +
      '  <form class="cdt-card cdt-auth-card" id="cdt-pwd-form">' +
      '    <div class="cdt-auth-icon">🔒</div>' +
      '    <h2>需要密码验证</h2>' +
      '    <p>此团队分享链接设置了访问密码</p>' +
      '    <div style="margin-top:20px;">' +
      '      <input class="cdt-input" id="cdt-pwd-input" type="password" placeholder="请输入访问密码" autocomplete="current-password" autofocus required />' +
      '    </div>' +
      (state.passwordError ? '<div class="cdt-error-text">' + esc(state.passwordError) + '</div>' : '') +
      '    <div style="margin-top:16px;">' +
      '      <button class="cdt-btn" type="submit"' + (state.verifying ? ' disabled' : '') + '>' +
      (state.verifying ? '验证中…' : '验证并查看') +
      '      </button>' +
      '    </div>' +
      '  </form>' +
      '</div>';

    var form = document.getElementById('cdt-pwd-form');
    if (form) {
      form.addEventListener('submit', function (e) {
        e.preventDefault();
        var input = document.getElementById('cdt-pwd-input');
        verifyPassword(input ? input.value.trim() : '');
      });
    }
  }

  function renderLoadAllHistoryBtn(truncated, label) {
    if (!truncated || truncated <= 0) return '';
    return (
      '<button class="cdt-load-more-btn" type="button" data-load-history="1"' +
      (state.loadingHistory ? ' disabled' : '') + '>' +
      (state.loadingHistory
        ? '正在加载全部历史…'
        : '加载全部' + esc(label) + '（还有 ' + truncated + ' 条）') +
      '</button>'
    );
  }

  function renderAnnouncements(announcements) {
    if (!announcements.length) return '';
    var itemsHtml = announcements.map(function (a) {
      var isPriority = a.is_priority === 1 || a.is_priority === true;
      return (
        '<div class="cdt-item' + (isPriority ? ' is-priority' : '') + '">' +
        '  <div class="cdt-item-title-row">' +
        '    <div class="cdt-item-title">' + esc(a.title || '团队公告') + '</div>' +
        (isPriority ? '<span class="cdt-tag warn">置顶</span>' : '') +
        '  </div>' +
        (a.content ? '<div class="cdt-item-body">' + esc(a.content) + '</div>' : '') +
        '  <div class="cdt-item-meta">' +
        (a.creator_name ? '<span>发布者：' + esc(a.creator_name) + '</span>' : '') +
        (a.created_at ? '<span>' + esc(formatDateTime(a.created_at, false)) + '</span>' : '') +
        '  </div>' +
        '</div>'
      );
    }).join('');

    return (
      '<section class="cdt-card cdt-section">' +
      '  <div class="cdt-section-head">' +
      '    <h2 class="cdt-section-title">团队公告</h2>' +
      '    <span class="cdt-count-badge">' + announcements.length + '</span>' +
      '  </div>' +
      '  <div class="cdt-list">' + itemsHtml + '</div>' +
      '</section>'
    );
  }

  function renderScheduleItem(item) {
    var timeText = formatScheduleTime(item);
    return (
      '<div class="cdt-item">' +
      '  <div class="cdt-item-title-row">' +
      '    <div class="cdt-item-title">' + esc(item.title || '未命名日程') + '</div>' +
      '  </div>' +
      '  <div class="cdt-item-meta">' +
      (timeText ? '<span class="cdt-tag">' + esc(timeText) + '</span>' : '') +
      (item.location ? '<span>📍 ' + esc(item.location) + '</span>' : '') +
      '  </div>' +
      (item.remark ? '<div class="cdt-item-body">' + esc(item.remark) + '</div>' : '') +
      '</div>'
    );
  }

  function renderSchedules(schedules, meta) {
    var totalCount = (meta && typeof meta.total === 'number') ? meta.total : schedules.length;
    if (!totalCount && !schedules.length) return '';
    var nowMs = Date.now();
    var active = [];
    var ended = [];
    schedules.forEach(function (item) {
      if (isScheduleEnded(item, nowMs)) ended.push(item);
      else active.push(item);
    });

    var truncated = (meta && typeof meta.truncated === 'number') ? meta.truncated : 0;
    var endedTotal = (meta && typeof meta.ended_total === 'number') ? meta.ended_total : ended.length;

    var activeHtml = active.length
      ? '<div class="cdt-list">' + active.map(renderScheduleItem).join('') + '</div>'
      : '<div class="cdt-item-meta">暂无进行中或即将开始的日程</div>';

    var endedSummary = truncated > 0
      ? '已结束日程 (已显示最近 ' + ended.length + ' 条，共 ' + endedTotal + ' 条)'
      : '已结束日程 (' + ended.length + ')';

    var endedHtml = (ended.length || truncated > 0)
      ? '<details class="cdt-details" id="cdt-details-schedules"><summary>' + endedSummary + '</summary><div class="cdt-list" style="margin-top:8px;">' +
        ended.map(renderScheduleItem).join('') +
        '</div>' + renderLoadAllHistoryBtn(truncated, '历史日程') + '</details>'
      : '';

    return (
      '<section class="cdt-card cdt-section">' +
      '  <div class="cdt-section-head">' +
      '    <h2 class="cdt-section-title">团队日程</h2>' +
      '    <span class="cdt-count-badge">' + totalCount + '</span>' +
      '  </div>' +
      activeHtml +
      endedHtml +
      '</section>'
    );
  }

  function isCountdownPast(c, startOfToday) {
    if (c.is_completed === 1 || c.is_completed === true) return true;
    if (!c.target_time) return false;
    var target = new Date(Number(c.target_time));
    if (isNaN(target.getTime())) return false;
    var startOfTarget = new Date(target.getFullYear(), target.getMonth(), target.getDate()).getTime();
    return startOfTarget < startOfToday;
  }

  function renderCountdownItem(c) {
    var done = c.is_completed === 1 || c.is_completed === true;
    var rem = formatCountdownRemaining(c.target_time, done);
    return (
      '<div class="cdt-item' + (done ? ' is-done' : '') + '">' +
      '  <div class="cdt-item-title-row">' +
      '    <div class="cdt-item-title">' + esc(c.title || '未命名倒计时') + '</div>' +
      (rem.text ? '<span class="cdt-tag ' + rem.cls + '">' + esc(rem.text) + '</span>' : '') +
      '  </div>' +
      '  <div class="cdt-item-meta">' +
      (c.target_time ? '<span>目标日期：' + esc(formatDate(c.target_time)) + '</span>' : '') +
      '  </div>' +
      '</div>'
    );
  }

  function renderCountdowns(countdowns, meta) {
    var totalCount = (meta && typeof meta.total === 'number') ? meta.total : countdowns.length;
    if (!totalCount && !countdowns.length) return '';
    var now = new Date();
    var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    var active = [];
    var past = [];
    countdowns.forEach(function (c) {
      if (isCountdownPast(c, startOfToday)) past.push(c);
      else active.push(c);
    });

    var truncated = (meta && typeof meta.truncated === 'number') ? meta.truncated : 0;
    var pastTotal = (meta && typeof meta.past_total === 'number') ? meta.past_total : past.length;

    var activeHtml = active.length
      ? '<div class="cdt-list">' + active.map(renderCountdownItem).join('') + '</div>'
      : '<div class="cdt-item-meta">暂无进行中的倒计时</div>';

    var pastSummary = truncated > 0
      ? '已经过 / 已完成倒计时 (已显示最近 ' + past.length + ' 条，共 ' + pastTotal + ' 条)'
      : '已经过 / 已完成倒计时 (' + past.length + ')';

    var pastHtml = (past.length || truncated > 0)
      ? '<details class="cdt-details" id="cdt-details-countdowns"><summary>' + pastSummary + '</summary><div class="cdt-list" style="margin-top:8px;">' +
        past.map(renderCountdownItem).join('') +
        '</div>' + renderLoadAllHistoryBtn(truncated, '历史倒计时') + '</details>'
      : '';

    return (
      '<section class="cdt-card cdt-section">' +
      '  <div class="cdt-section-head">' +
      '    <h2 class="cdt-section-title">倒计时</h2>' +
      '    <span class="cdt-count-badge">' + totalCount + '</span>' +
      '  </div>' +
      activeHtml +
      pastHtml +
      '</section>'
    );
  }

  function getTodoPastStatus(t, nowMs, startOfToday) {
    if (t.is_completed === 1 || t.is_completed === true) return 'done';
    if (t.due_date) {
      var dueMs = Number(t.due_date);
      if (!isNaN(dueMs) && dueMs > 0) {
        var isAllDay = t.is_all_day === 1 || t.isAllDay === true;
        var isOverdue = isAllDay ? dueMs < startOfToday : dueMs < nowMs;
        return isOverdue ? 'overdue' : 'active';
      }
    }
    var createdMs = Number(t.created_date || t.created_at || 0);
    if (!isNaN(createdMs) && createdMs > 0 && createdMs < startOfToday) {
      return 'past';
    }
    return 'active';
  }

  function renderTodoItem(t, status) {
    var done = t.is_completed === 1 || t.is_completed === true;
    var isAllDay = t.is_all_day === 1 || t.isAllDay === true;
    var dueText = t.due_date ? formatDateTime(t.due_date, isAllDay) : '';
    var createdText = !dueText && (t.created_date || t.created_at)
      ? formatDate(t.created_date || t.created_at)
      : '';
    var badgeHtml = status === 'overdue'
      ? '<span class="cdt-tag danger">已逾期</span>'
      : (status === 'past' ? '<span class="cdt-tag">历史待办</span>' : '');
    var metaText = dueText
      ? '截止：' + esc(dueText)
      : (createdText ? '创建于：' + esc(createdText) : '');

    return (
      '<div class="cdt-item' + (done ? ' is-done' : '') + '">' +
      '  <div class="cdt-todo-row">' +
      '    <span class="cdt-check' + (done ? ' checked' : '') + '">' + (done ? '✓' : '') + '</span>' +
      '    <div style="min-width:0;flex:1;">' +
      '      <div class="cdt-item-title-row">' +
      '        <div class="cdt-item-title">' + esc(t.content || '') + '</div>' +
      badgeHtml +
      '      </div>' +
      (metaText
        ? '<div class="cdt-item-meta"><span>' + metaText + '</span></div>'
        : '') +
      '    </div>' +
      '  </div>' +
      '</div>'
    );
  }

  function getTodoEffectiveDueMs(t) {
    if (!t.due_date) return 0;
    var dueMs = Number(t.due_date);
    if (isNaN(dueMs) || dueMs <= 0) return 0;
    var isAllDay = t.is_all_day === 1 || t.isAllDay === true;
    if (!isAllDay) return dueMs;
    var d = new Date(dueMs);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999).getTime();
  }

  function computeTodoProgress(t, nowMs) {
    var endMs = getTodoEffectiveDueMs(t);
    if (!endMs) return 0;
    var startMs = Number(t.created_date || t.created_at || 0);
    if (!startMs || endMs <= startMs || nowMs <= startMs) return 0;
    var ratio = (nowMs - startMs) / (endMs - startMs);
    return Math.max(0, Math.min(1, ratio));
  }

  function compareTodosByUrgency(a, b, nowMs) {
    var aDone = a.is_completed === 1 || a.is_completed === true;
    var bDone = b.is_completed === 1 || b.is_completed === true;
    if (aDone !== bDone) return aDone ? 1 : -1;

    var pDiff = computeTodoProgress(b, nowMs) - computeTodoProgress(a, nowMs);
    if (Math.abs(pDiff) > 1e-6) return pDiff;

    var aDue = getTodoEffectiveDueMs(a);
    var bDue = getTodoEffectiveDueMs(b);
    if (aDue && bDue && aDue !== bDue) return aDue - bDue;
    if (aDue && !bDue) return -1;
    if (!aDue && bDue) return 1;

    return Number(b.created_at || 0) - Number(a.created_at || 0);
  }

  function renderTodoGroups(entries, groups, nowMs) {
    var groupMap = {};
    var buckets = {};
    groups.forEach(function (g) {
      var gid = String(g.uuid || '');
      groupMap[gid] = g.name || '未命名分组';
      buckets[gid] = [];
    });
    var ungrouped = [];

    entries.forEach(function (entry) {
      var gid = entry.todo.group_id ? String(entry.todo.group_id) : '';
      if (gid && buckets[gid]) buckets[gid].push(entry);
      else ungrouped.push(entry);
    });

    var blocks = [];
    var groupList = [];
    groups.forEach(function (g) {
      var gid = String(g.uuid || '');
      var items = buckets[gid] || [];
      if (!items.length) return;
      items.sort(function (ea, eb) {
        return compareTodosByUrgency(ea.todo, eb.todo, nowMs);
      });
      var maxProgress = 0;
      var minDue = 0;
      items.forEach(function (e) {
        var p = computeTodoProgress(e.todo, nowMs);
        if (p > maxProgress) maxProgress = p;
        var d = getTodoEffectiveDueMs(e.todo);
        if (d && (!minDue || d < minDue)) minDue = d;
      });
      groupList.push({
        gid: gid,
        name: groupMap[gid],
        items: items,
        maxProgress: maxProgress,
        minDue: minDue
      });
    });

    groupList.sort(function (a, b) {
      if (Math.abs(b.maxProgress - a.maxProgress) > 1e-6) return b.maxProgress - a.maxProgress;
      if (a.minDue && b.minDue && a.minDue !== b.minDue) return a.minDue - b.minDue;
      if (a.minDue && !b.minDue) return -1;
      if (!a.minDue && b.minDue) return 1;
      return 0;
    });

    groupList.forEach(function (grp) {
      blocks.push(
        '<div class="cdt-group-block">' +
        '  <div class="cdt-group-title"><span>' + esc(grp.name) + '</span><span>' + grp.items.length + '</span></div>' +
        '  <div class="cdt-list">' + grp.items.map(function (e) { return renderTodoItem(e.todo, e.status); }).join('') + '</div>' +
        '</div>'
      );
    });

    if (ungrouped.length) {
      ungrouped.sort(function (ea, eb) {
        return compareTodosByUrgency(ea.todo, eb.todo, nowMs);
      });
      blocks.push(
        '<div class="cdt-group-block">' +
        (blocks.length ? '<div class="cdt-group-title"><span>未分组</span><span>' + ungrouped.length + '</span></div>' : '') +
        '  <div class="cdt-list">' + ungrouped.map(function (e) { return renderTodoItem(e.todo, e.status); }).join('') + '</div>' +
        '</div>'
      );
    }

    return blocks.join('');
  }

  function renderTodos(todos, groups, meta) {
    var totalCount = (meta && typeof meta.total === 'number') ? meta.total : todos.length;
    if (!totalCount && !todos.length) return '';
    var now = new Date();
    var nowMs = now.getTime();
    var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    var active = [];
    var pastOrOverdue = [];
    var completed = [];

    todos.forEach(function (t) {
      var status = getTodoPastStatus(t, nowMs, startOfToday);
      var entry = { todo: t, status: status };
      if (status === 'done') completed.push(entry);
      else if (status === 'overdue' || status === 'past') pastOrOverdue.push(entry);
      else active.push(entry);
    });

    var truncated = (meta && typeof meta.truncated === 'number') ? meta.truncated : 0;

    var activeHtml = active.length
      ? renderTodoGroups(active, groups, nowMs)
      : '<div class="cdt-item-meta">暂无进行中的待办</div>';

    var pastHtml = pastOrOverdue.length
      ? '<details class="cdt-details" id="cdt-details-todos-past"><summary>已逾期 / 历史待办 (' + pastOrOverdue.length + ')</summary><div style="margin-top:8px;">' +
        renderTodoGroups(pastOrOverdue, groups, nowMs) +
        '</div></details>'
      : '';

    var doneSummary = truncated > 0
      ? '已完成待办 (已显示最近 ' + completed.length + ' 条，还有 ' + truncated + ' 条更早记录)'
      : '已完成待办 (' + completed.length + ')';

    var doneHtml = (completed.length || truncated > 0)
      ? '<details class="cdt-details" id="cdt-details-todos-done"><summary>' + doneSummary + '</summary><div style="margin-top:8px;">' +
        renderTodoGroups(completed, groups, nowMs) +
        '</div>' + renderLoadAllHistoryBtn(truncated, '历史待办') + '</details>'
      : '';

    return (
      '<section class="cdt-card cdt-section">' +
      '  <div class="cdt-section-head">' +
      '    <h2 class="cdt-section-title">团队待办</h2>' +
      '    <span class="cdt-count-badge">' + totalCount + '</span>' +
      '  </div>' +
      activeHtml +
      pastHtml +
      doneHtml +
      '</section>'
    );
  }

  function renderJoinModal() {
    if (!state.joinOpen) return '';
    return (
      '<div class="cdt-modal-backdrop" id="cdt-join-backdrop">' +
      '  <form class="cdt-card cdt-modal" id="cdt-join-form">' +
      '    <h3>申请加入团队</h3>' +
      '    <p class="cdt-modal-desc">填写你的邮箱，管理员审批后你将收到通知。</p>' +
      '    <div class="cdt-field">' +
      '      <input class="cdt-input" id="cdt-join-email" type="email" placeholder="请输入你的注册邮箱" required />' +
      '    </div>' +
      '    <div class="cdt-field">' +
      '      <textarea class="cdt-input" id="cdt-join-msg" rows="3" placeholder="备注（可选）：简单介绍一下自己"></textarea>' +
      '    </div>' +
      (state.joinError ? '<div class="cdt-error-text">' + esc(state.joinError) + '</div>' : '') +
      '    <div class="cdt-modal-actions">' +
      '      <button class="cdt-btn cdt-btn-secondary" id="cdt-join-cancel" type="button">取消</button>' +
      '      <button class="cdt-btn" type="submit"' + (state.joinSubmitting ? ' disabled' : '') + '>' +
      (state.joinSubmitting ? '提交中…' : '提交申请') +
      '      </button>' +
      '    </div>' +
      '  </form>' +
      '</div>'
    );
  }

  function collectOpenDetailIds() {
    var ids = [];
    document.querySelectorAll('details.cdt-details[open]').forEach(function (el) {
      if (el.id) ids.push(el.id);
    });
    return ids;
  }

  function renderDashboard(openDetailIds) {
    var d = state.data || {};
    var share = d.share || {};
    var meta = d.history_meta || {};
    var teamName = (d.team && d.team.name) ? d.team.name : '未知团队';
    var shareTitle = share.title || teamName;
    var shareDesc = share.description || '';
    var todos = Array.isArray(d.todos) ? d.todos : [];
    var groups = Array.isArray(d.groups) ? d.groups : [];
    var schedules = parseScheduleList(d);
    var countdowns = Array.isArray(d.countdowns) ? d.countdowns : [];
    var announcements = Array.isArray(d.announcements) ? d.announcements : [];

    var totalTodos = (meta.todos && typeof meta.todos.total === 'number') ? meta.todos.total : todos.length;
    var totalSchedules = (meta.schedules && typeof meta.schedules.total === 'number') ? meta.schedules.total : schedules.length;
    var totalCountdowns = (meta.countdowns && typeof meta.countdowns.total === 'number') ? meta.countdowns.total : countdowns.length;

    var hasAny = totalTodos || totalSchedules || totalCountdowns || announcements.length;

    var leftCol = [
      renderAnnouncements(announcements),
      renderSchedules(schedules, meta.schedules),
      renderCountdowns(countdowns, meta.countdowns)
    ].filter(Boolean).join('');

    var rightCol = renderTodos(todos, groups, meta.todos);
    var hasTwoCols = Boolean(leftCol && rightCol);

    var stats = [];
    if (share.share_todos) stats.push('<div class="cdt-stat-pill">待办 <span>' + totalTodos + '</span></div>');
    if (share.share_schedules) stats.push('<div class="cdt-stat-pill">日程 <span>' + totalSchedules + '</span></div>');
    if (share.share_countdowns) stats.push('<div class="cdt-stat-pill">倒计时 <span>' + totalCountdowns + '</span></div>');
    if (share.share_announcements) stats.push('<div class="cdt-stat-pill">公告 <span>' + announcements.length + '</span></div>');

    document.title = shareTitle + ' · CountDownTodo';

    root.innerHTML =
      '<header class="cdt-share-hero">' +
      '  <div class="cdt-share-container">' +
      '    <div class="cdt-hero-top">' +
      '      <div class="cdt-hero-team-pill">' + esc(teamName) + '</div>' +
      '      <div class="cdt-hero-actions">' +
      '        <button class="cdt-icon-btn" id="cdt-refresh-btn" type="button">↻ 刷新</button>' +
      (window.cdtOpenFullApp
        ? '        <button class="cdt-icon-btn" id="cdt-open-full-btn" type="button">打开完整版</button>'
        : '') +
      '      </div>' +
      '    </div>' +
      '    <h1 class="cdt-hero-title">' + esc(shareTitle) + '</h1>' +
      (shareDesc ? '<p class="cdt-hero-desc">' + esc(shareDesc) + '</p>' : '') +
      '  </div>' +
      '</header>' +
      '<main class="cdt-share-main">' +
      '  <div class="cdt-share-container">' +
      '    <div class="cdt-card cdt-summary-card">' +
      '      <div class="cdt-summary-stats">' + (stats.join('') || '<span class="cdt-summary-meta">只读分享视图</span>') + '</div>' +
      '      <div class="cdt-summary-meta">分享码 ' + esc(state.code) + '</div>' +
      '    </div>' +
      (hasAny
        ? '<div class="cdt-grid' + (hasTwoCols ? ' has-two-cols' : '') + '">' +
          (leftCol ? '<div class="cdt-col">' + leftCol + '</div>' : '') +
          (rightCol ? '<div class="cdt-col">' + rightCol + '</div>' : '') +
          '</div>'
        : '<div class="cdt-card cdt-empty" style="margin-top:18px;">暂无公开的团队内容</div>') +
      '  </div>' +
      '</main>' +
      '<button class="cdt-fab" id="cdt-join-btn" type="button">＋ 申请加入团队</button>' +
      renderJoinModal();

    if (Array.isArray(openDetailIds)) {
      openDetailIds.forEach(function (id) {
        var el = document.getElementById(id);
        if (el) el.open = true;
      });
    }

    var refreshBtn = document.getElementById('cdt-refresh-btn');
    if (refreshBtn) {
      refreshBtn.addEventListener('click', function () {
        loadData({ forceNetwork: true });
      });
    }

    var openFullBtn = document.getElementById('cdt-open-full-btn');
    if (openFullBtn && window.cdtOpenFullApp) {
      openFullBtn.addEventListener('click', window.cdtOpenFullApp);
    }

    var joinBtn = document.getElementById('cdt-join-btn');
    if (joinBtn) {
      joinBtn.addEventListener('click', function () {
        state.joinOpen = true;
        state.joinError = '';
        render(collectOpenDetailIds());
      });
    }

    var cancelBtn = document.getElementById('cdt-join-cancel');
    if (cancelBtn) {
      cancelBtn.addEventListener('click', function () {
        state.joinOpen = false;
        render(collectOpenDetailIds());
      });
    }

    var backdrop = document.getElementById('cdt-join-backdrop');
    if (backdrop) {
      backdrop.addEventListener('click', function (e) {
        if (e.target === backdrop) {
          state.joinOpen = false;
          render(collectOpenDetailIds());
        }
      });
    }

    var joinForm = document.getElementById('cdt-join-form');
    if (joinForm) {
      joinForm.addEventListener('submit', function (e) {
        e.preventDefault();
        var emailEl = document.getElementById('cdt-join-email');
        var msgEl = document.getElementById('cdt-join-msg');
        submitJoin(emailEl ? emailEl.value.trim() : '', msgEl ? msgEl.value.trim() : '');
      });
    }

    root.querySelectorAll('[data-load-history]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        if (state.loadingHistory) return;
        var openIds = collectOpenDetailIds();
        var parentDetails = btn.closest('details');
        if (parentDetails && parentDetails.id && openIds.indexOf(parentDetails.id) === -1) {
          openIds.push(parentDetails.id);
        }
        state.includeHistory = true;
        state.loadingHistory = true;
        render(openIds);
        loadData({
          forceNetwork: true,
          includeHistory: true,
          keepDashboard: true,
          openDetailIds: openIds
        });
      });
    });
  }

  function render(openDetailIds) {
    if (state.loading && !state.data) return renderLoading();
    if (state.needsPassword) return renderPassword();
    if (state.error && !state.data) return renderError();
    return renderDashboard(openDetailIds);
  }

  function handleDataResponse(json, opts) {
    state.loading = false;
    state.loadingHistory = false;
    if (json && json.success) {
      state.needsPassword = false;
      state.data = json;
    } else if (json && json.error === 'Password required') {
      state.needsPassword = true;
    } else {
      if (!opts.keepDashboard) {
        state.error = (json && json.error) || '加载失败';
      } else {
        showToast((json && json.error) || '加载失败');
      }
    }
    render(opts.openDetailIds);
  }

  function loadData(opts) {
    opts = opts || {};
    var includeHistory = opts.includeHistory !== undefined
      ? Boolean(opts.includeHistory)
      : state.includeHistory;

    if (!opts.forceNetwork && !includeHistory && !state.token) {
      if (window.__CDT_INITIAL_SHARE_DATA__) {
        var embedded = window.__CDT_INITIAL_SHARE_DATA__;
        window.__CDT_INITIAL_SHARE_DATA__ = null;
        handleDataResponse(embedded, opts);
        return;
      }

      var prefetched = window.__cdtSharePrefetch;
      if (prefetched && prefetched.code === state.code && !prefetched.consumed && prefetched.promise) {
        prefetched.consumed = true;
        state.loading = true;
        state.error = '';
        render();
        prefetched.promise
          .then(function (json) { handleDataResponse(json, opts); })
          .catch(function () {
            state.loading = false;
            state.error = '网络请求失败，请检查网络连接';
            render();
          });
        return;
      }
    }

    if (!opts.keepDashboard) {
      state.loading = true;
      state.error = '';
      render();
    }

    var params = ['tz_offset=' + encodeURIComponent(String(new Date().getTimezoneOffset()))];
    if (state.token) {
      params.push('token=' + encodeURIComponent(state.token));
    }
    if (includeHistory) {
      params.push('include_history=1');
    }

    var url = API_BASE + '/api/shares/' + encodeURIComponent(state.code) + '/data?' + params.join('&');

    fetch(url, { method: 'GET' })
      .then(function (res) { return res.json(); })
      .then(function (json) { handleDataResponse(json, opts); })
      .catch(function () {
        state.loading = false;
        state.loadingHistory = false;
        if (!opts.keepDashboard) {
          state.error = '网络请求失败，请检查网络连接';
        } else {
          showToast('网络请求失败，请稍后重试');
        }
        render(opts.openDetailIds);
      });
  }

  function verifyPassword(password) {
    if (!password) return;
    state.verifying = true;
    state.passwordError = '';
    render();

    fetch(API_BASE + '/api/shares/' + encodeURIComponent(state.code) + '/verify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password: password })
    })
      .then(function (res) { return res.json(); })
      .then(function (json) {
        state.verifying = false;
        if (json && json.success && !json.requires_password) {
          state.token = json.access_token || null;
          state.needsPassword = false;
          loadData({ forceNetwork: true });
        } else {
          state.passwordError = (json && json.error) || '密码错误';
          render();
        }
      })
      .catch(function () {
        state.verifying = false;
        state.passwordError = '验证请求失败，请重试';
        render();
      });
  }

  function submitJoin(email, message) {
    if (!email) {
      state.joinError = '请输入邮箱';
      render(collectOpenDetailIds());
      return;
    }
    state.joinSubmitting = true;
    state.joinError = '';
    render(collectOpenDetailIds());

    var joinBody = { email: email, message: message };
    if (state.token) {
      joinBody.token = state.token;
    }
    var joinHeaders = { 'Content-Type': 'application/json' };
    if (state.token) {
      joinHeaders['X-Share-Token'] = state.token;
    }

    fetch(API_BASE + '/api/shares/' + encodeURIComponent(state.code) + '/request_join', {
      method: 'POST',
      headers: joinHeaders,
      body: JSON.stringify(joinBody)
    })
      .then(function (res) { return res.json(); })
      .then(function (json) {
        state.joinSubmitting = false;
        if (json && json.success) {
          state.joinOpen = false;
          render(collectOpenDetailIds());
          showToast('申请已提交，请等待管理员审批');
        } else {
          state.joinError = (json && json.error) || '提交失败';
          render(collectOpenDetailIds());
        }
      })
      .catch(function () {
        state.joinSubmitting = false;
        state.joinError = '网络请求失败，请重试';
        render(collectOpenDetailIds());
      });
  }

  if (state.code) {
    loadData();
  } else {
    state.loading = false;
    state.error = '缺少分享码';
    render();
  }
})();
