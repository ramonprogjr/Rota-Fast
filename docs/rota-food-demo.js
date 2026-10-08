(() => {
  const targets = [...document.querySelectorAll('[data-demo]')];
  if (!targets.length) return;

  const storageKey = 'rota-food-interview-demo-v1';
  const defaultOrigin = {
    name: 'Pizzaria Sabor da Vila',
    city: 'São Bernardo do Campo',
    address: 'Rua Jurubatuba, 460, Centro, São Bernardo do Campo, SP',
    latitude: -23.6944,
    longitude: -46.5654,
  };
  const origin = { ...defaultOrigin };
  const starterDeliveries = [
    { id: 'ana', name: 'Ana Souza', address: 'Rua das Flores, 120, Centro, São Bernardo do Campo, SP', latitude: -23.6925, longitude: -46.559, priority: 'urgent', value: 8, done: false },
    { id: 'marcos', name: 'Marcos Lima', address: 'Av. Kennedy, 456, Jardim do Mar, São Bernardo do Campo, SP', latitude: -23.684, longitude: -46.565, priority: 'high', value: 9, done: false },
    { id: 'joao', name: 'João Pedro', address: 'Rua Jurubatuba, 88, Centro, São Bernardo do Campo, SP', latitude: -23.7006, longitude: -46.5746, priority: 'normal', value: 8, done: false },
    { id: 'maria', name: 'Maria Costa', address: 'Rua Marechal Deodoro, 1500, Centro, São Bernardo do Campo, SP', latitude: -23.706, longitude: -46.562, priority: 'normal', value: 10, done: false },
  ];
  const initialState = {
    deliveries: starterDeliveries,
    odometerKm: 12500,
    simulatedKm: 0,
    lastCompletedDeliveryId: null,
    lastOilChangeKm: 11580,
    gasPriceLiter: 6,
    kmPerLiter: 30,
    establishment: { ...defaultOrigin },
  };

  function readState() {
    try {
      const saved = JSON.parse(localStorage.getItem(storageKey));
      if (saved && Array.isArray(saved.deliveries)) {
        return { ...initialState, ...saved, establishment: { ...defaultOrigin, ...(saved.establishment ?? {}) } };
      }
    } catch (_) {
      // Keep the demo usable when browser storage is unavailable.
    }
    return structuredClone(initialState);
  }

  function syncOriginFromState() {
    const current = state.establishment ?? defaultOrigin;
    Object.assign(origin, defaultOrigin, current);
  }

  let state = readState();
  syncOriginFromState();
  let activeScreen = 'home';
  let selectedDeliveryId = state.deliveries.find(item => !item.done)?.id ?? null;
  let geocodeResults = [];
  let lastGeocodeAt = 0;
  let statusMessage = '';
  let statusKind = '';

  const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[character]);
  const priorityLabels = { urgent: 'Urgente', high: 'Alta', normal: 'Normal' };
  const priorityWeights = { urgent: 0.4, high: 0.7, normal: 1 };
  const pending = () => state.deliveries.filter(item => !item.done);
  const done = () => state.deliveries.filter(item => item.done);
  const currentOdometer = () => state.odometerKm + (state.simulatedKm ?? 0);
  const oilRemaining = () => Math.max(0, 1000 - Math.max(0, currentOdometer() - state.lastOilChangeKm));
  const money = value => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(value);
  const formatKm = value => `${value.toFixed(1).replace('.', ',')} km`;

  function saveState() {
    try {
      localStorage.setItem(storageKey, JSON.stringify(state));
    } catch (_) {
      statusMessage = 'Os dados ficam apenas nesta demonstração e não puderam ser salvos pelo navegador.';
      statusKind = 'warning';
    }
  }

  function haversineKm(aLat, aLng, bLat, bLng) {
    const radians = degrees => degrees * Math.PI / 180;
    const latitudeDelta = radians(bLat - aLat);
    const longitudeDelta = radians(bLng - aLng);
    const value = Math.sin(latitudeDelta / 2) ** 2 +
      Math.cos(radians(aLat)) * Math.cos(radians(bLat)) * Math.sin(longitudeDelta / 2) ** 2;
    return 6371 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
  }

  function optimizeRoute() {
    const pendingItems = pending();
    const remaining = pendingItems.filter(item => Number.isFinite(item.latitude) && Number.isFinite(item.longitude));
    const withoutCoordinates = pendingItems.filter(item => !Number.isFinite(item.latitude) || !Number.isFinite(item.longitude));
    const ordered = [];
    const lastCompleted = state.deliveries.find(item => item.id === state.lastCompletedDeliveryId);
    let latitude = lastCompleted?.latitude ?? origin.latitude;
    let longitude = lastCompleted?.longitude ?? origin.longitude;
    let totalKm = 0;

    while (remaining.length) {
      let bestIndex = 0;
      let bestScore = Infinity;
      let bestDistance = 0;
      remaining.forEach((item, index) => {
        const distance = haversineKm(latitude, longitude, item.latitude, item.longitude);
        const score = distance * (priorityWeights[item.priority] ?? 1);
        if (score < bestScore) {
          bestIndex = index;
          bestScore = score;
          bestDistance = distance;
        }
      });
      const next = remaining.splice(bestIndex, 1)[0];
      ordered.push({ ...next, legKm: bestDistance });
      totalKm += bestDistance;
      latitude = next.latitude;
      longitude = next.longitude;
    }
    withoutCoordinates.forEach(item => ordered.push({ ...item, legKm: null }));
    return { ordered, totalKm, estimatedMinutes: Math.ceil(totalKm / 28 * 60), withoutCoordinates };
  }

  function go(screen) {
    activeScreen = screen;
    statusMessage = '';
    statusKind = '';
    renderAll();
  }

  function note(message = statusMessage, kind = statusKind) {
    return message ? `<p class="status-note ${kind}">${escapeHtml(message)}</p>` : '';
  }

  function button(action, label, style = 'secondary', extra = '') {
    return `<button type="button" class="mini-action ${style}" data-action="${action}" ${extra}>${label}</button>`;
  }

  function deliveryCard(item, index, showControls = true) {
    const hasPoint = Number.isFinite(item.latitude) && Number.isFinite(item.longitude);
    const tag = item.done ? '<span class="priority" style="color:var(--green)">ENTREGUE</span>' :
      `<span class="priority">${escapeHtml(priorityLabels[item.priority] ?? 'Normal').toUpperCase()}</span>`;
    const controls = showControls && !item.done
      ? `<div class="delivery-controls">
          <select aria-label="Prioridade de ${escapeHtml(item.name)}" data-action="priority" data-id="${escapeHtml(item.id)}">
            ${Object.entries(priorityLabels).map(([key, label]) => `<option value="${key}" ${item.priority === key ? 'selected' : ''}>${label}</option>`).join('')}
          </select>
          <button type="button" data-action="delivered" data-id="${escapeHtml(item.id)}">Entregue</button>
          <button type="button" class="icon-action" aria-label="Remover ${escapeHtml(item.name)}" data-action="remove" data-id="${escapeHtml(item.id)}">×</button>
        </div>`
      : '';
    return `<article class="delivery">
      <div class="delivery-top"><span class="num">${item.done ? '✓' : index + 1}</span><span>${escapeHtml(item.name || 'Cliente')}</span>${tag}</div>
      <p>${escapeHtml(item.address)}<br><span style="color:${hasPoint ? 'var(--green)' : 'var(--yellow)'}">${hasPoint ? 'Ponto de demonstração confirmado' : 'Sem coordenadas; será resolvido pelo Maps'}</span></p>
      ${controls}
    </article>`;
  }

  function routeStats(route) {
    const estimate = route.estimatedMinutes < 60
      ? `~${route.estimatedMinutes} min`
      : `~${Math.floor(route.estimatedMinutes / 60)}h ${String(route.estimatedMinutes % 60).padStart(2, '0')}min`;
    return `<div class="mini-stats">
      <div class="mini-stat"><strong>${pending().length}</strong><span>pendentes</span></div>
      <div class="mini-stat"><strong>${formatKm(route.totalKm)}</strong><span>linha reta</span></div>
      <div class="mini-stat"><strong>${estimate}</strong><span>estimativa</span></div>
    </div>`;
  }

  function homeScreen() {
    const route = optimizeRoute();
    const oil = oilRemaining();
    return `<div class="mini-banner"><div><strong>${escapeHtml(origin.name)}</strong><span>São Bernardo do Campo</span></div><span>DEMO</span></div>
      ${routeStats(route)}
      ${oil <= 100 ? `<div class="oil-warning">Óleo: faltam ${oil.toFixed(0)} km para a troca.</div>` : ''}
      ${note()}
      <div class="inline-actions">${button('route', '⌁ Organizar rota')}${button('add', '+ Pedido')}</div>
      <div class="inline-actions">${button('settings', '⚙ Ajustes')}${button('report', '▤ Relatório')}</div>
      <div class="mini-section">Entregas do turno</div>
      ${pending().length ? route.ordered.map((item, index) => deliveryCard(item, index)).join('') : '<p class="status-note">Todas as entregas foram concluídas.</p>'}
      ${done().length ? `<div class="mini-section">Concluídas (${done().length})</div>${done().map((item, index) => deliveryCard(item, index, false)).join('')}` : ''}
      <p class="demo-notice">Dados fictícios salvos somente nesta demonstração.</p>`;
  }

  function addScreen() {
    return `<p class="status-note">Os endereços digitados ficam como texto. Para ordenar por distância nesta demo, use um ponto localizado ou os endereços de exemplo.</p>
      ${note()}
      <form data-form="delivery">
        <label class="field"><span class="form-label">CLIENTE</span><input name="name" placeholder="Nome do cliente" required /></label>
        <label class="field"><span class="form-label">ENDEREÇO COMPLETO</span><textarea name="address" placeholder="Rua, número, bairro, cidade" required></textarea></label>
        <label class="field"><span class="form-label">PRIORIDADE</span><select name="priority"><option value="normal">Normal</option><option value="high">Alta</option><option value="urgent">Urgente</option></select></label>
        <div class="inline-actions">${button('locate', '⌖ Localizar', 'secondary')}<button type="submit" class="mini-action">Salvar pedido</button></div>
      </form>
      ${geocodeResults.length ? `<div class="mini-section">Escolha o ponto</div>${geocodeResults.map((item, index) => `<button type="button" class="delivery" style="width:100%;color:var(--paper);text-align:left;cursor:pointer" data-action="select-geocode" data-index="${index}"><span class="delivery-top">Opção ${index + 1}</span><p>${escapeHtml(item.display_name)}</p></button>`).join('')}<p class="osm-credit">Busca por OpenStreetMap/Nominatim. O texto do endereço é enviado ao serviço.</p>` : ''}
      <div class="mini-section">Adicionar exemplo localizado</div>
      ${button('sample-delivery', '＋ Adicionar parada de exemplo', 'secondary')}
      ${button('back-home', 'Voltar', 'secondary')}`;
  }

  function pasteScreen() {
    return `<p class="status-note">Cole uma entrega por linha. Formato: nome — endereço. Novas linhas entram sem coordenadas e ficam no fim da sequência estimada.</p>
      ${note()}
      <label class="field"><span class="form-label">ENDEREÇOS</span><textarea name="batch" placeholder="João — Rua Marechal Deodoro, 1500, Centro, São Bernardo do Campo&#10;Maria — Av. Kennedy, 456, São Bernardo do Campo"></textarea></label>
      <div data-role="batch-preview" class="status-note">Digite para conferir os pedidos.</div>
      ${button('import-batch', '＋ Salvar entregas', '')}${button('back-home', 'Voltar', 'secondary')}`;
  }

  function mapScreen() {
    const item = state.deliveries.find(delivery => delivery.id === selectedDeliveryId) ?? pending()[0];
    return `<div class="field"><small>ENDEREÇO</small><span>${escapeHtml(item?.address ?? 'Nenhuma entrega pendente')}</span></div>
      <div class="map-art" style="height:235px"><span class="map-road one"></span><span class="map-road two"></span><span class="map-pin"><span>1</span></span><span class="map-label">${escapeHtml(item?.name ?? 'Origem')}</span></div>
      <p class="status-note">Mapa ilustrativo para a apresentação. Confirme endereços no Google Maps antes de usar.</p>
      ${item && !Number.isFinite(item.latitude) ? '<p class="osm-credit">Este endereço ainda não tem coordenadas nesta demo.</p>' : ''}
      ${button('route', '⌁ Ver rota organizada')}${button('navigate', '➤ Abrir destino no Maps', '')}${button('back-home', 'Voltar', 'secondary')}`;
  }

  function routeScreen() {
    const route = optimizeRoute();
    const estimate = route.estimatedMinutes < 60
      ? `~${route.estimatedMinutes} min`
      : `~${Math.floor(route.estimatedMinutes / 60)}h ${String(route.estimatedMinutes % 60).padStart(2, '0')}min`;
    const stops = route.ordered.map((item, index) => `<article class="delivery route-stop">
      <span class="num">${index + 1}</span><span class="stop-copy"><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(item.address)}</small></span>
      <span>${item.legKm == null ? '<em>sem ponto</em>' : `<em>${formatKm(item.legKm)}</em>`}</span>
    </article>`).join('');
    return `<div class="mini-banner"><div><strong>${pending().length} entregas pendentes</strong><span>Partida: ${escapeHtml(origin.name)}</span></div><span>ROTA</span></div>
      <div class="mini-stats"><div class="mini-stat"><strong>${formatKm(route.totalKm)}</strong><span>linha reta</span></div><div class="mini-stat"><strong>${estimate}</strong><span>estimativa</span></div><div class="mini-stat"><strong>${route.withoutCoordinates.length}</strong><span>sem ponto</span></div></div>
      ${note()}
      ${stops || '<p class="status-note">Adicione uma entrega para montar a rota.</p>'}
      ${route.withoutCoordinates.length ? '<p class="status-note warning">Endereços sem coordenadas aparecem no fim e não entram na estimativa.</p>' : ''}
      ${button('organize', '↻ Recalcular rota', 'secondary')}${button('navigate-route', '➤ Abrir rota no Google Maps', '')}${button('back-home', 'Voltar', 'secondary')}
      <p class="demo-notice">Distância em linha reta; o Maps recalcula o trajeto pelas ruas.</p>`;
  }

  function settingsScreen() {
    return `<p class="status-note">Ajustes demonstrativos: os valores não alteram o APK.</p>
      ${note()}
      <div class="mini-section">Estabelecimento</div>
      <label class="field"><span class="form-label">NOME</span><input name="establishment-name" type="text" value="${escapeHtml(origin.name)}" /></label>
      <label class="field"><span class="form-label">ENDEREÇO</span><textarea name="establishment-address">${escapeHtml(origin.address)}</textarea></label>
      <label class="field"><span class="form-label">CIDADE</span><input name="establishment-city" type="text" value="${escapeHtml(origin.city || 'São Bernardo do Campo')}" /></label>
      <div class="inline-actions">
        <label class="field" style="flex:1"><span class="form-label">LAT</span><input name="establishment-lat" type="number" step="0.0001" value="${origin.latitude}" /></label>
        <label class="field" style="flex:1"><span class="form-label">LNG</span><input name="establishment-lng" type="number" step="0.0001" value="${origin.longitude}" /></label>
      </div>
      <div class="mini-section">Moto: gasolina e óleo</div>
      <label class="field"><span class="form-label">PREÇO DO LITRO (R$)</span><input name="gas-price" type="number" min="0" step="0.01" value="${state.gasPriceLiter}" /></label>
      <label class="field"><span class="form-label">CONSUMO (KM/L)</span><input name="km-liter" type="number" min="0" step="0.1" value="${state.kmPerLiter}" /></label>
      <label class="field"><span class="form-label">HODÔMETRO ATUAL (KM)</span><input name="odometer" type="number" min="0" step="1" value="${currentOdometer().toFixed(1)}" /></label>
      <label class="field"><span class="form-label">HODÔMETRO DA ÚLTIMA TROCA (KM)</span><input name="last-oil" type="number" min="0" step="1" value="${state.lastOilChangeKm}" /></label>
      <p class="status-note ${oilRemaining() <= 100 ? 'warning' : ''}">Intervalo de óleo: 1.000 km. ${oilRemaining() <= 100 ? `Faltam ${oilRemaining().toFixed(0)} km.` : `Faltam ${oilRemaining().toFixed(0)} km para a troca.`}</p>
      ${button('save-settings', 'Salvar ajustes', '')}${button('back-home', 'Voltar', 'secondary')}`;
  }

  function reportScreen() {
    const route = optimizeRoute();
    const earnings = done().reduce((sum, item) => sum + (Number(item.value) || 0), 0);
    const fuel = state.simulatedKm > 0 && state.kmPerLiter > 0 ? state.simulatedKm / state.kmPerLiter * state.gasPriceLiter : 0;
    const oil = oilRemaining();
    return `<div class="report-title"><span>Resumo demonstrativo</span><span style="color:var(--green)">● DEMO</span></div>
      <div class="report-grid"><div class="report-metric"><span>PENDENTES</span><strong>${pending().length}</strong></div><div class="report-metric"><span>CONCLUÍDAS</span><strong>${done().length}</strong></div><div class="report-metric"><span>KM DA DEMO</span><strong>${formatKm(state.simulatedKm ?? 0)}</strong></div><div class="report-metric"><span>GASOLINA EST.</span><strong>${money(fuel)}</strong></div><div class="report-metric"><span>VALOR CONCLUÍDO</span><strong>${money(earnings)}</strong></div><div class="report-metric"><span>ÓLEO</span><strong>${oil.toFixed(0)} km</strong></div></div>
      <p class="status-note ${oil <= 100 ? 'warning' : ''}">${oil <= 100 ? `Atenção: faltam ${oil.toFixed(0)} km para a troca.` : `Faltam ${oil.toFixed(0)} km para a próxima troca (intervalo de 1.000 km).`}</p>
      <p class="demo-notice">Km e gasolina são estimativas demonstrativas; no app, o percurso do turno vem do GPS.</p>
      ${button('settings', '⚙ Ajustar hodômetro e óleo', 'secondary')}${button('back-home', 'Voltar', 'secondary')}`;
  }

  function scanScreen() {
    return `<div class="mini-banner"><div><strong>Leitura de comanda</strong><span>Disponível no app Android</span></div><span>OCR</span></div>
      <p class="status-note">O OCR do projeto usa Google ML Kit no aparelho e não é executado neste protótipo web.</p>
      ${button('add', '＋ Cadastrar pedido manualmente', '')}${button('sample-delivery', '＋ Adicionar pedido de exemplo', 'secondary')}${button('back-home', 'Voltar', 'secondary')}`;
  }

  const screenTitles = {
    home: 'Rota Food', add: 'Nova entrega', paste: 'Colar endereços', map: 'Confirmar local',
    route: 'Rota do turno', report: 'Linha do tempo', settings: 'Estabelecimento e ajustes', scan: 'Fotografar comandas',
  };
  const screenContent = { home: homeScreen, add: addScreen, paste: pasteScreen, map: mapScreen, route: routeScreen, report: reportScreen, settings: settingsScreen, scan: scanScreen };
  const screenLabels = [['home', 'Início'], ['add', 'Pedido'], ['paste', 'Colar'], ['scan', 'OCR'], ['map', 'Mapa'], ['route', 'Rota'], ['report', 'Relatório'], ['settings', 'Ajustes']];

  function renderPhone(target, screenKey) {
    target.innerHTML = `<div class="phone"><div class="phone-screen">
      <div class="statusbar"><span>9:41</span><span>● ● ●　▰</span></div>
      <div class="appbar">
        <div class="appbar-title">${screenKey === 'home' ? '' : '<button type="button" data-action="back-home" aria-label="Voltar">‹</button>'}<span>${screenTitles[screenKey]}</span></div>
        <div class="appbar-actions">${screenKey === 'home' ? '<button type="button" data-action="report" aria-label="Relatório">▤</button><button type="button" data-action="settings" aria-label="Ajustes">⚙</button><button type="button" data-action="add" aria-label="Nova entrega">＋</button>' : ''}</div>
      </div>
      <div class="phone-body" data-role="phone-body">${screenContent[screenKey]()}</div>
      <div class="phone-nav" aria-hidden="true"><span class="gesture-line"></span></div>
    </div></div>
    <p class="screen-caption">Protótipo interativo · dados demonstrativos</p>
    <div class="screen-picker" role="group" aria-label="Telas da demonstração">${screenLabels.map(([key, label]) => `<button class="screen-tab ${key === screenKey ? 'active' : ''}" type="button" data-screen="${key}" aria-pressed="${key === screenKey}">${label}</button>`).join('')}</div>`;
  }

  function renderAll(screen = activeScreen) {
    activeScreen = screen;
    targets.forEach(target => renderPhone(target, screen));
    saveState();
  }

  function addSampleDelivery() {
    const samples = [
      { name: 'Pedro Alves', address: 'Rua Santa Filomena, 240, Centro, São Bernardo do Campo, SP', latitude: -23.6912, longitude: -46.5632, priority: 'normal', value: 8 },
      { name: 'Clara Mendes', address: 'Av. Lucas Nogueira Garcez, 880, Jardim do Mar, São Bernardo do Campo, SP', latitude: -23.688, longitude: -46.5518, priority: 'high', value: 10 },
      { name: 'Rafael Santos', address: 'Rua dos Vianas, 900, Baeta Neves, São Bernardo do Campo, SP', latitude: -23.7045, longitude: -46.5485, priority: 'normal', value: 9 },
    ];
    const sample = samples.find(item => !state.deliveries.some(delivery => delivery.address === item.address)) ?? samples[0];
    state.deliveries.push({ ...sample, id: `sample-${Date.now()}`, done: false });
    statusMessage = `${sample.name} entrou nas entregas pendentes.`;
    statusKind = 'success';
    go('home');
  }

  function addCustomDelivery(phoneBody) {
    const form = phoneBody.querySelector('[data-form="delivery"]');
    if (!form.reportValidity()) return;
    const latitude = Number(form.dataset.latitude);
    const longitude = Number(form.dataset.longitude);
    state.deliveries.push({
      id: `custom-${Date.now()}`,
      name: form.elements.name.value.trim(),
      address: form.elements.address.value.trim(),
      priority: form.elements.priority.value,
      value: 0,
      latitude: Number.isFinite(latitude) ? latitude : null,
      longitude: Number.isFinite(longitude) ? longitude : null,
      done: false,
    });
    geocodeResults = [];
    statusMessage = 'Pedido salvo. Sem ponto confirmado, ele fica no fim da estimativa e o Maps localizará o endereço escrito.';
    statusKind = 'warning';
    go('home');
  }

  function addBatch(phoneBody) {
    const text = phoneBody.querySelector('[name="batch"]')?.value ?? '';
    const lines = text.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
    if (!lines.length) {
      statusMessage = 'Cole pelo menos um endereço.';
      statusKind = 'warning';
      renderAll('paste');
      return;
    }
    lines.forEach((line, index) => {
      const parts = line.split(/\s+[—–-]\s+/, 2);
      state.deliveries.push({
        id: `batch-${Date.now()}-${index}`,
        name: parts.length > 1 ? parts[0].trim() : `Cliente ${index + 1}`,
        address: (parts.length > 1 ? parts[1] : parts[0]).trim(),
        priority: 'normal', value: 0, latitude: null, longitude: null, done: false,
      });
    });
    statusMessage = `${lines.length} pedido(s) adicionado(s). Endereços sem coordenadas serão enviados ao Maps como texto.`;
    statusKind = 'success';
    go('home');
  }

  async function locateAddress(phoneBody) {
    const query = phoneBody.querySelector('[name="address"]')?.value.trim();
    if (!query) {
      statusMessage = 'Digite o endereço antes de localizar.';
      statusKind = 'warning';
      renderAll('add');
      return;
    }
    const wait = Math.max(0, 1000 - (Date.now() - lastGeocodeAt));
    if (wait) await new Promise(resolve => setTimeout(resolve, wait));
    lastGeocodeAt = Date.now();
    statusMessage = 'Buscando opções no OpenStreetMap…';
    statusKind = '';
    renderAll('add');
    try {
      const url = new URL('https://nominatim.openstreetmap.org/search');
      url.search = new URLSearchParams({ q: `${query}, São Bernardo do Campo, SP, Brasil`, format: 'jsonv2', limit: '5', countrycodes: 'br' });
      const response = await fetch(url, { headers: { 'Accept-Language': 'pt-BR' } });
      if (!response.ok) throw new Error('Busca indisponível');
      const results = await response.json();
      geocodeResults = results.filter(item => Number.isFinite(Number(item.lat)) && Number.isFinite(Number(item.lon))).map(item => ({
        display_name: item.display_name,
        latitude: Number(item.lat),
        longitude: Number(item.lon),
      }));
      statusMessage = geocodeResults.length ? 'Escolha o resultado que corresponde ao endereço.' : 'Nenhum ponto encontrado. O pedido ainda pode ser salvo como texto.';
      statusKind = geocodeResults.length ? 'success' : 'warning';
    } catch (_) {
      geocodeResults = [];
      statusMessage = 'Não consegui consultar o OpenStreetMap. Confira a conexão ou salve como endereço sem ponto.';
      statusKind = 'warning';
    }
    renderAll('add');
  }

  function selectGeocode(screenContainer, index) {
    const result = geocodeResults[index];
    const form = screenContainer.querySelector('[data-form="delivery"]');
    if (!result || !form) return;
    statusMessage = 'Ponto selecionado. Salve o pedido para incluir na sequência.';
    statusKind = 'success';
    renderAll('add');
    const newForm = screenContainer.querySelector('[data-form="delivery"]');
    newForm.elements.address.value = result.display_name;
    newForm.dataset.latitude = result.latitude;
    newForm.dataset.longitude = result.longitude;
  }

  function openMaps(routeOnly) {
    const route = optimizeRoute();
    const items = route.ordered;
    if (!items.length) {
      statusMessage = 'Adicione uma entrega antes de abrir o Maps.';
      statusKind = 'warning';
      renderAll('route');
      return;
    }
    const directions = new URL('https://www.google.com/maps/dir/');
    directions.searchParams.set('api', '1');
    directions.searchParams.set('origin', origin.address);
    directions.searchParams.set('destination', items[items.length - 1].address);
    directions.searchParams.set('travelmode', 'driving');
    if (items.length > 1) {
      directions.searchParams.set('waypoints', items.slice(0, -1).map(item => item.address).join('|'));
    }
    window.open(directions.toString(), '_blank', 'noopener,noreferrer');
  }

  function handleClick(event, target) {
    const screenButton = event.target.closest('[data-screen]');
    if (screenButton) {
      event.preventDefault();
      go(screenButton.dataset.screen);
      return;
    }
    const buttonElement = event.target.closest('[data-action]');
    if (!buttonElement) return;
    event.preventDefault();
    const action = buttonElement.dataset.action;
    const phoneBody = target.querySelector('[data-role="phone-body"]');
    const item = state.deliveries.find(delivery => delivery.id === buttonElement.dataset.id);

    if (action === 'add' || action === 'route' || action === 'paste' || action === 'map' || action === 'report' || action === 'settings' || action === 'scan') {
      if (action === 'map') selectedDeliveryId = pending()[0]?.id ?? null;
      go(action);
    } else if (action === 'back-home') go('home');
    else if (action === 'sample-delivery') addSampleDelivery();
    else if (action === 'save-delivery') addCustomDelivery(phoneBody);
    else if (action === 'locate') locateAddress(phoneBody);
    else if (action === 'select-geocode') selectGeocode(target, Number(buttonElement.dataset.index));
    else if (action === 'import-batch') addBatch(phoneBody);
    else if (action === 'organize') {
      statusMessage = 'Rota recalculada pela distância em linha reta e prioridade.';
      statusKind = 'success';
      go('route');
    } else if (action === 'navigate-route') openMaps(true);
    else if (action === 'navigate') openMaps(false);
    else if (action === 'delivered' && item) {
      const routeItem = optimizeRoute().ordered.find(delivery => delivery.id === item.id);
      const drivenKm = routeItem?.legKm ?? 0;
      item.done = true;
      if (Number.isFinite(item.latitude) && Number.isFinite(item.longitude)) {
        state.simulatedKm = (state.simulatedKm ?? 0) + drivenKm;
        state.lastCompletedDeliveryId = item.id;
        statusMessage = `${item.name} entregue. ${formatKm(drivenKm)} estimados somados ao controle de óleo e ao relatório.`;
      } else {
        statusMessage = `${item.name} entregue. Sem coordenadas, não foi possível estimar km para o óleo; ajuste o hodômetro em Ajustes.`;
      }
      statusKind = 'success';
      go('home');
    } else if (action === 'remove' && item) {
      state.deliveries = state.deliveries.filter(delivery => delivery.id !== item.id);
      statusMessage = 'Pedido removido da demonstração.';
      statusKind = 'success';
      go('home');
    } else if (action === 'save-settings') {
      const name = (phoneBody.querySelector('[name="establishment-name"]').value || '').trim() || defaultOrigin.name;
      const address = (phoneBody.querySelector('[name="establishment-address"]').value || '').trim() || defaultOrigin.address;
      const city = (phoneBody.querySelector('[name="establishment-city"]').value || '').trim() || defaultOrigin.city;
      const latitude = Number(phoneBody.querySelector('[name="establishment-lat"]').value);
      const longitude = Number(phoneBody.querySelector('[name="establishment-lng"]').value);

      state.establishment = {
        name,
        address,
        city,
        latitude: Number.isFinite(latitude) ? latitude : defaultOrigin.latitude,
        longitude: Number.isFinite(longitude) ? longitude : defaultOrigin.longitude,
      };
      syncOriginFromState();

      state.gasPriceLiter = Math.max(0, Number(phoneBody.querySelector('[name="gas-price"]').value) || 0);
      state.kmPerLiter = Math.max(0, Number(phoneBody.querySelector('[name="km-liter"]').value) || 0);
      state.odometerKm = Math.max(0, Number(phoneBody.querySelector('[name="odometer"]').value) || 0);
      state.simulatedKm = 0;
      state.lastOilChangeKm = Math.max(0, Number(phoneBody.querySelector('[name="last-oil"]').value) || 0);
      statusMessage = 'Estabelecimento e dados da moto salvos. A rota e a origem da entrega já foram atualizados.';
      statusKind = 'success';
      go('settings');
    }
  }

  function handleChange(event, target) {
    const priority = event.target.closest('[data-action="priority"]');
    if (priority) {
      const item = state.deliveries.find(delivery => delivery.id === priority.dataset.id);
      if (item) item.priority = priority.value;
      renderAll(activeScreen);
      return;
    }
    if (event.target.name === 'batch') {
      const preview = target.querySelector('[data-role="batch-preview"]');
      const count = event.target.value.split(/\r?\n/).filter(line => line.trim()).length;
      if (preview) preview.textContent = count ? `${count} endereço(s) reconhecido(s).` : 'Digite para conferir os pedidos.';
    }
  }

  targets.forEach(target => {
    target.addEventListener('click', event => handleClick(event, target));
    target.addEventListener('change', event => handleChange(event, target));
    target.addEventListener('submit', event => {
      if (event.target.matches('[data-form="delivery"]')) {
        event.preventDefault();
        addCustomDelivery(target.querySelector('[data-role="phone-body"]'));
      }
    });
  });

  renderAll('home');
})();