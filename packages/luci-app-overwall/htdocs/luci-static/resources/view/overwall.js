'use strict';
'require view';
'require dom';
'require rpc';
'require ui';
'require poll';
'require network';

var getStatus = rpc.declare({ object: 'luci.overwall', method: 'status', expect: {}, timeout: 120000 });
var execute = rpc.declare({ object: 'luci.overwall', method: 'command', params: ['action', 'data'], expect: {}, timeout: 120000 });
var getJob = rpc.declare({ object: 'luci.overwall', method: 'job', params: ['id'], expect: {}, timeout: 10000 });
var states = { connected: _('Подключено'), disconnected: _('Отключено'), restricted: _('Доступ ограничен'), error: _('Ошибка подключения') };

return view.extend({
	handleSaveApply: null, handleSave: null, handleReset: null,
	load: function() { return Promise.all([getStatus(), network.getNetworks()]); },
	act: function(action, data) {
		var visual = action !== 'pair_poll';
		if (visual) { this.busyAction = action; if (this.root) this.draw(); }
		return execute(action, JSON.stringify(data || {})).then(L.bind(function(result) {
			if (result.error) throw new Error(result.error);
			if (!result.job_id) return result;
			var deadline = Date.now() + 190000;
			var check = function() {
				return getJob(result.job_id).then(function(job) {
					if (job.error) throw new Error(job.error);
					if (job.done) { if (job.result.error) throw new Error(job.result.error); return job.result; }
					if (Date.now() > deadline) throw new Error(_('Операция не завершилась. Проверьте состояние VPN перед повтором.'));
					return new Promise(function(resolve) { setTimeout(resolve, 700); }).then(check);
				});
			};
			return check();
		}, this)).catch(function(error) {
			ui.addNotification(null, E('p', { role: 'alert' }, error.message), 'error'); throw error;
		}).finally(L.bind(function() { if (visual) { this.busyAction = null; if (this.root && !this.settingsDirty) this.draw(); } }, this));
	},
	button: function(label, fn, primary, options) {
		options = options || {};
		return E('button', { type: 'button', 'class': 'ow-btn ' + (primary ? 'ow-primary ' : '') + (options.className || ''), 'aria-label': options.ariaLabel || label, disabled: options.disabled || !!this.busyAction ? '' : null, 'click': ui.createHandlerFn(this, function(event) {
			var button = event.currentTarget; button.disabled = true;
			return Promise.resolve(fn.call(this)).then(L.bind(this.update, this)).catch(function() {}).finally(function() { button.disabled = false; });
		}) }, label);
	},
	importDialog: function() {
		var name = E('input', { id: 'ow-source-name', name: 'source-name', placeholder: _('Например, мой VPN…'), maxlength: 100, autocomplete: 'off' });
		var kind = E('select', { id: 'ow-source-kind', name: 'source-kind' }, [E('option', { value: 'url' }, _('Ссылка на подписку')), E('option', { value: 'text' }, _('VLESS, Base64 или JSON')), E('option', { value: 'wireguard' }, _('Конфигурация WireGuard'))]);
		var value = E('textarea', { id: 'ow-source-value', name: 'source-value', rows: 7, spellcheck: 'false', autocomplete: 'off', placeholder: 'https://provider.example/subscription…' });
		var error = E('p', { 'class': 'ow-inline-error', role: 'alert' });
		var file = E('input', { id: 'ow-source-file', name: 'source-file', type: 'file', accept: '.conf,.txt,.json', 'aria-label': _('Загрузить файл конфигурации'), change: function() {
			if (!file.files.length) return;
			if (file.files[0].size > 2097152) { error.textContent = _('Файл больше 2 МБ. Выберите файл меньшего размера.'); return; }
			return file.files[0].text().then(function(text) { value.value = text; error.textContent = ''; if (/\.conf$/i.test(file.files[0].name)) kind.value = 'wireguard'; kind.dispatchEvent(new Event('change')); }).catch(function() { error.textContent = _('Не удалось прочитать файл. Попробуйте вставить его содержимое.'); });
		} });
		kind.addEventListener('change', function() { value.placeholder = kind.value === 'url' ? 'https://provider.example/subscription…' : kind.value === 'wireguard' ? '[Interface]\nPrivateKey = …\nAddress = …\n\n[Peer]\nPublicKey = …' : 'vless://…'; });
		var body = E('div', { 'class': 'ow-modal' }, [E('p', { 'class': 'ow-help' }, _('Добавьте своего провайдера или готовую конфигурацию. Вход в Overwall не нужен — данные останутся на роутере.')), E('div', { 'class': 'ow-field' }, [E('label', { 'for': 'ow-source-name' }, _('Как назвать подключение')), name]), E('div', { 'class': 'ow-field' }, [E('label', { 'for': 'ow-source-kind' }, _('Что добавляем')), kind]), E('div', { 'class': 'ow-field' }, [E('label', { 'for': 'ow-source-value' }, _('Ссылка или содержимое конфигурации')), value]), E('div', { 'class': 'ow-field' }, [E('label', { 'for': 'ow-source-file' }, _('Или выберите файл')), file]), E('p', { 'class': 'ow-help' }, _('Поддерживаются VLESS-подписки и обычный WireGuard с одним Peer. Ключи не отправляются в Overwall.')), error, E('div', { 'class': 'ow-actions' }, [this.button(_('Отмена'), function() { value.value = ''; ui.hideModal(); }, false, { className: 'ow-quiet' }), this.button(_('Добавить подключение'), function() {
			if (!name.value.trim()) { error.textContent = _('Введите название подключения.'); name.setAttribute('aria-invalid', 'true'); name.focus(); return; }
			if (!value.value.trim()) { error.textContent = _('Вставьте ссылку или конфигурацию.'); value.setAttribute('aria-invalid', 'true'); value.focus(); return; }
			return this.act('add', { name: name.value, kind: kind.value, value: value.value }).then(function() { value.value = ''; ui.hideModal(); }).catch(function() { error.textContent = _('Подключение не добавлено. Проверьте формат и попробуйте ещё раз.'); });
		}, true)])]);
		ui.showModal(_('Своё подключение'), [body]);
	},
	pairDialog: function() {
		return this.act('pair').then(L.bind(function(pair) {
			var uri = new URL(pair.verification_uri);
			if (uri.origin !== 'https://overwall.online' || uri.pathname !== '/client/tv/activate') throw new Error(_('Некорректный адрес подтверждения'));
			var expires = Date.now() + pair.expires_in * 1000, cancelled = false;
			var hint = E('p', { 'class': 'ow-help', role: 'status', 'aria-live': 'polite' }, _('После подтверждения серверы появятся автоматически.'));
			var tick = L.bind(function() {
				if (cancelled) return;
				if (Date.now() > expires) { hint.textContent = _('Код истёк. Закройте окно и запросите новый.'); poll.remove(tick); return; }
				return this.act('pair_poll').then(L.bind(function(result) { if (result.success) { cancelled = true; poll.remove(tick); ui.hideModal(); return this.update(); } }, this));
			}, this);
			ui.showModal(_('Подключите аккаунт Overwall'), [E('div', { 'class': 'ow-modal' }, [E('p', { 'class': 'ow-help' }, _('Отсканируйте QR-код камерой телефона или откройте сайт. Войдите в свой аккаунт и подтвердите совпадающий код.')), E('div', { 'class': 'ow-pair' }, [pair.qr_svg ? E('img', { alt: _('QR-код для входа в Overwall'), width: 180, height: 180, src: 'data:image/svg+xml;base64,' + btoa(pair.qr_svg) }) : '', E('div', {}, [E('p', { 'class': 'ow-help' }, _('Код на этом роутере')), E('p', { 'class': 'ow-pair-code' }, pair.user_code), E('a', { 'class': 'ow-btn ow-primary', href: uri.href, target: '_blank', rel: 'noopener noreferrer' }, _('Открыть сайт для входа ↗'))])]), hint, E('div', { 'class': 'ow-actions' }, this.button(_('Закрыть'), function() { cancelled = true; poll.remove(tick); ui.hideModal(); }, false, { className: 'ow-quiet' }))])]);
			poll.add(tick, Math.max(5, pair.poll_interval));
		}, this));
	},
	allNodes: function(protocol) {
		var result = [];
		(this.status.sources || []).forEach(function(source) {
			source.nodes.forEach(function(node, index) { if (!protocol || node.protocol === protocol) result.push({ source: source, node: node, index: index }); });
		});
		return result;
	},
	formatBytes: function(value) {
		if (value == null || !Number.isFinite(Number(value))) return '—';
		return new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 1 }).format(Number(value) / 1073741824);
	},
	badge: function(label, kind) { return E('span', { 'class': 'ow-badge ' + (kind ? 'is-' + kind : '') }, label); },
	update: function() {
		return getStatus().then(L.bind(function(status) {
			var changed = JSON.stringify(status) !== JSON.stringify(this.status);
			this.status = status;
			if (changed && !this.settingsDirty && !this.searchFocused) this.draw();
		}, this));
	},
	setTab: function(tab) {
		if (this.settingsDirty && tab !== 'settings' && !window.confirm(_('Не сохранять изменения настроек?'))) return;
		this.settingsDirty = false; this.settingsDraft = null; this.search = ''; this.sourceFilter = ''; this.tab = tab;
		window.history.replaceState(null, '', '#' + tab);
		this.draw();
	},
	serverCard: function(item) {
		var source = item.source, node = item.node, status = this.status;
		var active = status.state === 'connected' && status.selected === source.id && Number(status.node) === item.index;
		var wg = node.protocol === 'wireguard', own = source.kind !== 'overwall', owner = node.ownership || {};
		var busy = wg && !own && owner.state === 'busy', preparing = wg && node.state === 'preparing';
		var noAccess = !own && (wg ? node.state === 'access_required' : source.access && source.access.state !== 'active');
		var title = wg && node.location ? node.location : node.name;
		var flag = (title || '').match(/^([\uD83C][\uDDE6-\uDDFF][\uD83C][\uDDE6-\uDDFF])/);
		var label = flag ? title.slice(flag[0].length).trim() : title;
		var marker = flag ? flag[0] : wg ? 'W' : 'V';
		var subtitle = wg ? (own ? _('Собственная конфигурация') : _('Профиль ') + node.slot + (node.name && node.name !== title ? ' · ' + node.name : '')) : source.name;
		var indicator = active ? this.badge(_('Подключён'), 'good') : busy ? this.badge(_('Занят'), 'warn') : preparing ? this.badge(_('Готовится')) : wg && !own ? this.badge(owner.state === 'mine' ? _('Этот роутер') : owner.state === 'free' ? _('Свободен') : _('Без привязки'), owner.state === 'mine' ? 'good' : null) : this.badge(own ? _('Свой сервер') : 'Overwall');
		var action;
		if (active) action = this.button(_('Отключить'), function() { return this.act('disconnect'); }, false, { ariaLabel: _('Отключить ') + label });
		else if (noAccess) action = E('a', { 'class': 'ow-btn', href: 'https://overwall.online/', target: '_blank', rel: 'noopener noreferrer' }, _('Открыть кабинет'));
		else action = this.button(busy ? _('Занят другим устройством') : preparing ? _('Создаётся…') : _('Подключить'), function() { return this.act('connect', { id: source.id, node: item.index }); }, false, { disabled: busy || preparing, ariaLabel: _('Подключить ') + label });
		var content = [
			E('div', { 'class': 'ow-server-head' }, [E('span', { 'class': 'ow-location', 'aria-hidden': 'true' }, marker), E('div', { 'class': 'ow-server-title' }, [E('h4', {}, label || _('Без названия')), E('p', { 'class': 'ow-server-subtitle' }, subtitle)])]),
			E('div', { 'class': 'ow-server-footer' }, [E('div', { 'class': 'ow-meta' }, [this.badge(wg ? 'WireGuard' : 'VLESS'), indicator]), action])
		];
		if (busy) content.push(E('p', { 'class': 'ow-owner' }, _('Назначен устройству: ') + (owner.name || _('другое устройство')) + '. ' + _('Выберите свободный профиль.')));
		if (wg && !own && owner.state === 'unknown') content.push(E('p', { 'class': 'ow-owner' }, _('Использование старого профиля не подтверждено. Привязка появится после подключения.')));
		if (wg && active && !own) content.push(this.button(_('Отключить и освободить профиль'), function() { return this.act('release'); }, false, { className: 'ow-quiet' }));
		if (wg && node.details) {
			var params = [];
			[['Адрес VPN', node.details.address], ['DNS', node.details.dns || _('По умолчанию')], ['Сервер', node.details.endpoint]].forEach(function(pair) { params.push(E('dt', {}, pair[0]), E('dd', {}, pair[1] || '—')); });
			content.push(E('details', {}, [E('summary', {}, _('Параметры конфигурации')), E('dl', { 'class': 'ow-params' }, params)]));
		}
		return E('article', { 'class': 'ow-server' + (active ? ' is-active' : ''), 'aria-label': label || node.name }, content);
	},
	renderServerList: function() {
		var protocol = this.tab === 'wireguard' ? 'wireguard' : 'vless';
		var query = (this.search || '').trim().toLocaleLowerCase('ru-RU'), sourceFilter = this.sourceFilter || '';
		var all = this.allNodes(protocol), filtered = all.filter(function(item) { return (!sourceFilter || item.source.id === sourceFilter) && (!query || [item.node.name, item.node.location, item.source.name].join(' ').toLocaleLowerCase('ru-RU').includes(query)); });
		var cards = filtered.map(L.bind(this.serverCard, this));
		if (!cards.length) {
			var emptyTitle = query || sourceFilter ? _('Ничего не найдено') : protocol === 'wireguard' ? _('Здесь появятся ваши профили WireGuard') : _('Здесь появятся серверы VLESS');
			cards.push(E('div', { 'class': 'ow-empty' }, [E('span', { 'class': 'ow-empty-symbol', 'aria-hidden': 'true' }, '◇'), E('h3', {}, emptyTitle), E('p', {}, query || sourceFilter ? _('Попробуйте другое название или выберите все источники.') : _('Войдите в аккаунт Overwall или добавьте своё подключение. Серверы и профили загрузятся автоматически.')), !query && !sourceFilter ? this.button(_('Добавить своё подключение'), this.importDialog, true) : '']));
		}
		dom.content(this.serverList, cards);
	},
	serverPanel: function() {
		var wg = this.tab === 'wireguard';
		var search = E('input', { type: 'search', name: 'server-search', placeholder: _('Найти сервер…'), 'aria-label': _('Поиск серверов'), autocomplete: 'off', value: this.search || '', input: L.bind(function(event) { this.search = event.target.value; this.renderServerList(); }, this), focus: L.bind(function() { this.searchFocused = true; }, this), blur: L.bind(function() { this.searchFocused = false; }, this) });
		var toolbar = [search];
		if (this.status.sources.length > 1) {
			var sources = E('select', { name: 'server-source', 'aria-label': _('Источник серверов'), change: L.bind(function(event) { this.sourceFilter = event.target.value; this.renderServerList(); }, this) }, [E('option', { value: '' }, _('Все источники'))].concat(this.status.sources.map(function(source) { return E('option', { value: source.id }, source.name); })));
			sources.value = this.sourceFilter || ''; toolbar.push(sources);
		}
		this.serverList = E('div', { 'class': 'ow-server-list' }); this.renderServerList();
		return E('div', {}, [E('div', { 'class': 'ow-section-heading' }, [E('div', {}, [E('h3', {}, wg ? _('Профили WireGuard') : _('Серверы VLESS')), E('p', {}, wg ? _('Отдельные профили с понятной привязкой к устройствам.') : _('Выберите направление и подключите всю сеть.'))]), E('div', { 'class': 'ow-toolbar' }, toolbar)]), this.serverList]);
	},
	sourcesPanel: function() {
		var sources = this.status.sources.map(L.bind(function(source) {
			var last = source.updated_at ? new Intl.DateTimeFormat('ru-RU', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }).format(new Date(source.updated_at * 1000)) : null;
			var buttons = [];
			if (source.kind === 'url' || source.kind === 'overwall') buttons.push(this.button(_('Обновить'), function() { return this.act('refresh', { id: source.id }); }));
			buttons.push(this.button(source.kind === 'overwall' ? _('Выйти из аккаунта') : _('Удалить'), function() {
				if (!window.confirm(source.kind === 'overwall' ? _('Выйти из Overwall? Свои подписки и конфигурации останутся на роутере.') : _('Удалить это подключение? Если оно активно, VPN отключится.'))) return;
				return this.act(source.kind === 'overwall' ? 'logout' : 'remove', { id: source.id });
			}, false, { className: 'ow-quiet' }));
			return E('article', { 'class': 'ow-panel ow-source' }, [E('div', { 'class': 'ow-source-body' }, [E('h4', {}, source.name), E('p', {}, source.kind === 'overwall' ? source.email || _('Аккаунт Overwall') : source.kind === 'wireguard' ? _('Свой WireGuard-конфиг · хранится на роутере') : _('Своя подписка · независимо от Overwall')), E('p', {}, _('Подключения: ') + source.nodes.length + (last ? ' · ' + _('Обновлено ') + last : ''))]), E('div', { 'class': 'ow-actions' }, buttons)]);
		}, this));
		if (!sources.length) sources.push(E('div', { 'class': 'ow-empty' }, [E('h3', {}, _('Пока нет подключений')), E('p', {}, _('Добавьте ссылку на подписку или WireGuard-конфигурацию.'))]));
		return E('div', {}, [E('div', { 'class': 'ow-section-heading' }, [E('div', {}, [E('h3', {}, _('Ваши подключения')), E('p', {}, _('Управляйте аккаунтом Overwall и собственными источниками.'))]), this.button(_('Добавить подключение'), this.importDialog, true)]), E('div', { 'class': 'ow-source-list' }, sources)]);
	},
	settingsPanel: function() {
		var status = this.status, draft = this.settingsDraft || { network: status.network, autostart: status.autostart };
		this.settingsDraft = draft;
		var choices = this.networks.filter(function(net) { return !['wan', 'wan6', 'loopback', 'ow_wg'].includes(net.getName()); }).map(function(net) { return E('option', { value: net.getName() }, net.getName() === 'lan' ? _('Основная сеть (LAN)') : net.getName()); });
		var lan = E('select', { id: 'ow-network', name: 'protected-network', disabled: status.state !== 'disconnected' ? '' : null, change: L.bind(function(event) { draft.network = event.target.value; this.settingsDirty = true; }, this) }, choices); lan.value = draft.network;
		var auto = E('input', { type: 'checkbox', name: 'autostart', change: L.bind(function(event) { draft.autostart = event.target.checked; this.settingsDirty = true; }, this) }); auto.checked = !!draft.autostart;
		return E('div', { 'class': 'ow-settings' }, [E('div', { 'class': 'ow-section-heading' }, E('div', {}, [E('h3', {}, _('Сеть и автозапуск')), E('p', {}, _('VPN применяется ко всем устройствам выбранной сети.'))])), E('div', { 'class': 'ow-field' }, [E('label', { 'for': 'ow-network' }, _('Какие устройства подключать через VPN')), lan, E('p', {}, status.state !== 'disconnected' ? _('Сначала отключите VPN, чтобы изменить сеть.') : _('Для гостевой сети выберите её имя из списка.'))]), E('label', { 'class': 'ow-check' }, [auto, E('div', {}, [E('strong', {}, _('Подключаться после перезагрузки')), E('p', {}, _('Роутер автоматически восстановит последнее выбранное подключение.'))])]), E('div', { 'class': 'ow-panel' }, [E('h4', {}, _('Защита при обрыве соединения')), E('p', { 'class': 'ow-muted ow-small', style: 'margin-top:8px' }, _('Прямой выход в интернет блокируется, если VPN перестал работать. IPv6 выбранной сети также блокируется. Для обычного интернета явно отключите VPN.'))]), E('div', { 'class': 'ow-actions', style: 'margin-top:18px' }, this.button(_('Сохранить настройки'), function() { return this.act('settings', { network: draft.network, autostart: draft.autostart }).then(L.bind(function() { this.settingsDirty = false; this.settingsDraft = null; }, this)); }, true))]);
	},
	draw: function() {
		var status = this.status, sources = status.sources || [], account = sources.find(function(source) { return source.kind === 'overwall'; });
		var selected = this.allNodes().find(function(item) { return item.source.id === status.selected && item.index === Number(status.node); });
		var connected = status.state === 'connected', connecting = this.busyAction === 'connect';
		var title = connecting ? _('Подключаем VPN…') : connected ? _('Ваша сеть защищена') : status.state === 'restricted' ? _('Нужно восстановить доступ') : status.state === 'error' ? _('Проверьте подключение') : _('VPN отключён');
		var subtitle = connected && selected ? selected.node.name + ' · ' + (selected.node.protocol === 'wireguard' ? 'WireGuard' : 'VLESS') : status.protected ? _('Прямой выход заблокирован. Подключите VPN или отключите защиту.') : _('Выберите сервер ниже, чтобы подключить устройства к VPN.');
		var mainAction = connected || status.protected ? this.button(_('Отключить VPN'), function() { return this.act('disconnect'); }, true) : selected ? this.button(_('Подключить снова'), function() { return this.act('connect', { id: selected.source.id, node: selected.index }); }, true) : this.button(status.signed_in ? _('Выбрать сервер') : _('Войти в Overwall'), status.signed_in ? function() { this.setTab('vless'); } : this.pairDialog, true);
		var connection = E('section', { 'class': 'ow-panel ow-connection' }, [E('div', { 'class': 'ow-connection-main' }, [E('div', { 'class': 'ow-power' + (connected ? ' is-on' : ''), 'aria-hidden': 'true' }, E('span', { 'class': connecting ? 'ow-spin' : '' }, connecting ? '◌' : '⏻')), E('div', {}, [E('div', { 'class': 'ow-eyebrow' }, 'OVERWALL VPN'), E('h2', { 'aria-live': 'polite' }, title), E('p', { 'class': 'ow-muted ow-small' }, subtitle)])]), E('div', { 'class': 'ow-connection-bottom' }, [mainAction, E('span', { 'class': 'ow-network' }, [E('span', { 'class': 'ow-dot' + (connected ? ' is-on' : ''), 'aria-hidden': 'true' }), _('Сеть: ') + status.network])])]);
		var accountContent;
		if (account) {
			var access = account.access || {}, total = Number(access.total_bytes), remaining = access.remaining_bytes;
			var progress = remaining != null && total > 0 ? E('progress', { 'class': 'ow-progress', max: total, value: Math.max(0, Number(remaining)), 'aria-label': _('Остаток трафика VLESS') }) : '';
			accountContent = [E('div', { 'class': 'ow-account-head' }, [E('span', { 'class': 'ow-account-name' }, _('Ваш Overwall')), this.badge(access.state === 'active' ? _('Доступен') : _('Нужен доступ'), access.state === 'active' ? 'good' : 'warn')]), E('p', { 'class': 'ow-account-mail' }, account.email || _('Аккаунт подключён')), E('div', { 'class': 'ow-quota' }, [E('strong', {}, this.formatBytes(remaining)), E('span', {}, _('ГБ осталось'))]), E('p', { 'class': 'ow-muted ow-small' }, _('Трафик VLESS') + (total > 0 ? ' · ' + _('из ') + this.formatBytes(total) + ' ГБ' : '')), progress, E('div', { 'class': 'ow-meta ow-small ow-muted' }, [account.wireguard && account.wireguard.state !== 'access_required' ? this.badge(_('WireGuard без лимита'), 'good') : E('span', {}, _('WireGuard по условиям тарифа')), E('a', { href: 'https://overwall.online/', target: '_blank', rel: 'noopener noreferrer' }, _('Личный кабинет ↗'))])];
		} else accountContent = [E('div', { 'class': 'ow-account-head' }, E('span', { 'class': 'ow-account-name' }, _('Подключите Overwall'))), E('p', { 'class': 'ow-muted', style: 'margin:10px 0 18px' }, _('Войдите по коду: серверы, трафик и профили WireGuard появятся здесь.')), this.button(_('Войти в аккаунт'), this.pairDialog, false), E('p', { 'class': 'ow-muted ow-small', style: 'margin-top:12px' }, _('Свои подписки работают и без аккаунта.'))];
		var tabs = [['vless', 'VLESS', this.allNodes('vless').length], ['wireguard', 'WireGuard', this.allNodes('wireguard').length], ['sources', _('Подключения'), sources.length], ['settings', _('Настройки'), null]];
		var content = [E('header', { 'class': 'ow-top' }, [E('div', { 'class': 'ow-brand' }, [E('span', { 'class': 'ow-mark', 'aria-hidden': 'true' }, '◈'), E('div', {}, [E('strong', { translate: 'no' }, 'overwall'), E('small', {}, _('VPN для вашего роутера'))])]), E('div', { 'class': 'ow-actions' }, [this.button(_('＋ Своё подключение'), this.importDialog, false), account ? this.button(_('Обновить серверы'), function() { return this.act('refresh', { id: account.id }); }, false, { className: 'ow-quiet' }) : ''])]), E('div', { 'class': 'ow-hero-grid' }, [connection, E('section', { 'class': 'ow-panel ow-account', 'aria-label': _('Аккаунт и трафик') }, accountContent)])];
		if (status.portal) content.push(E('div', { 'class': 'ow-notice', role: 'status' }, [E('p', {}, status.portal.reason === 'connection_failed' ? _('Не удалось проверить VPN. На устройствах показана страница с диагностикой и предложением Overwall.') : _('Доступ выбранного подключения ограничен. Откройте кабинет: после восстановления доступа роутер подключится автоматически.')), E('a', { 'class': 'ow-btn', href: 'https://overwall.online/', target: '_blank', rel: 'noopener noreferrer' }, _('Открыть кабинет'))]));
		if (status.notice) content.push(E('div', { 'class': 'ow-notice', role: 'status' }, E('p', {}, _('Не удалось обновить данные аккаунта. Проверьте доступ к сайту. Сохранённая авторизация остаётся на роутере.'))));
		content.push(E('nav', { 'class': 'ow-tabs', role: 'tablist', 'aria-label': _('Разделы Overwall') }, tabs.map(L.bind(function(tab) { return E('button', { type: 'button', 'class': 'ow-tab', id: 'ow-tab-' + tab[0], role: 'tab', 'aria-controls': 'ow-panel', 'aria-selected': this.tab === tab[0] ? 'true' : 'false', tabindex: this.tab === tab[0] ? '0' : '-1', click: L.bind(function() { this.setTab(tab[0]); }, this), keydown: L.bind(function(event) { if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return; event.preventDefault(); var index = tabs.findIndex(function(item) { return item[0] === tab[0]; }); index = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length; this.setTab(tabs[index][0]); this.root.querySelector('#ow-tab-' + tabs[index][0]).focus(); }, this) }, [tab[1], tab[2] != null ? E('span', { 'class': 'ow-count' }, String(tab[2])) : '']); }, this))));
		content.push(E('section', { id: 'ow-panel', role: 'tabpanel', 'aria-labelledby': 'ow-tab-' + this.tab }, this.tab === 'sources' ? this.sourcesPanel() : this.tab === 'settings' ? this.settingsPanel() : this.serverPanel()));
		content.push(E('footer', { 'class': 'ow-footer' }, [E('span', {}, _('Ключи и свои конфигурации хранятся на роутере.')), E('a', { href: 'https://overwall.online/', target: '_blank', rel: 'noopener noreferrer' }, 'Overwall · ' + (status.version || '0.1.0'))]));
		dom.content(this.root, content);
	},
	render: function(data) {
		if (!document.getElementById('overwall-style')) document.head.appendChild(E('link', { id: 'overwall-style', rel: 'stylesheet', href: L.resource('overwall/style.css') + '?v=0.1.0-ui2' }));
		this.status = data[0]; this.networks = data[1]; this.search = ''; this.sourceFilter = ''; this.tab = window.location.hash.slice(1);
		if (!['vless', 'wireguard', 'sources', 'settings'].includes(this.tab)) this.tab = this.allNodes('vless').length || !this.allNodes('wireguard').length ? 'vless' : 'wireguard';
		this.root = E('div', { 'class': 'ow-app' }); this.draw();
		window.addEventListener('beforeunload', L.bind(function(event) { if (this.settingsDirty) { event.preventDefault(); event.returnValue = ''; } }, this));
		poll.add(L.bind(this.update, this), 10);
		return this.root;
	}
});
