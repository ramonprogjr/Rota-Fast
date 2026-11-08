# ROTA MAX
## Documento Mestre do Produto e Escopo de Desenvolvimento

**Slogan:** Sua rota. Seu controle. Seu resultado.

**Categoria:** Roteirização, logística e gestão de entregas  
**Plataforma inicial:** Android  
**Framework:** Flutter  
**Linguagem:** Dart  
**Banco de dados:** SQLite  
**Modelo inicial:** Aplicativo offline-first  
**Referência de mercado:** Spoke Route Planner (antigo Circuit)

---

# 1. VISÃO GERAL DO PRODUTO

O Rota Max é um aplicativo de planejamento, otimização e gerenciamento de rotas de entrega, desenvolvido para entregadores autônomos, motoristas de aplicativos de entrega e pequenas operações logísticas.

A proposta é transformar uma lista desorganizada de pedidos em uma rota inteligente, organizada, navegável e acompanhada do início ao fim.

O aplicativo deve permitir que o usuário cadastre endereços, importe pedidos, utilize OCR para extrair informações de fotografias, otimize a sequência de entregas e acompanhe sua produtividade.

## 1.1 Objetivos principais

1. Reduzir o tempo gasto organizando entregas.
2. Otimizar a sequência dos endereços.
3. Reduzir quilômetros percorridos.
4. Facilitar a importação de pedidos.
5. Automatizar a leitura de etiquetas e endereços.
6. Permitir acompanhamento das entregas.
7. Registrar produtividade e histórico.
8. Funcionar mesmo sem conexão com a internet, dentro das limitações dos serviços externos.

## 1.2 Público-alvo

- Entregadores autônomos.
- Motoristas de transportadoras.
- Entregadores de marketplaces.
- Motoristas de pequenas empresas.
- Operadores logísticos.
- Profissionais que trabalham com múltiplas entregas por dia.

## 1.3 Capacidade inicial

O aplicativo deverá suportar:

- Mínimo de 5 paradas.
- Operação recomendada de 5 a 40 paradas por rota.
- Importação de múltiplos pedidos.
- Processamento de até 5 fotografias por lote de OCR.
- Armazenamento local.
- Recuperação de rotas interrompidas.

---

# 2. BENCHMARK: SPOKE ROUTE PLANNER

O Spoke, anteriormente conhecido como Circuit, é uma referência de mercado para o Rota Max.

Suas funcionalidades servem como inspiração para a experiência do usuário e os recursos de roteirização.

## 2.1 Funcionalidades de referência

| Funcionalidade | Descrição |
|---|---|
| Importação de pedidos | Cadastro manual e importação em lote |
| Otimização | Reorganização automática das paradas |
| Prioridades | Definição de entregas prioritárias |
| Janelas de entrega | Consideração de horários específicos |
| ETA | Previsão de chegada |
| Navegação | Integração com aplicativos de GPS |
| Alteração de rota | Modificação durante a execução |
| Pausas | Inclusão de intervalos |
| Histórico | Consulta de rotas anteriores |

## 2.2 Estratégia competitiva

O Rota Max deverá utilizar conceitos semelhantes aos do Spoke, desenvolvendo diferenciais próprios.

Principais diferenciais:

- Interface em português.
- OCR para leitura de etiquetas.
- Operação offline-first.
- Importação simplificada de pedidos.
- Experiência adaptada ao entregador brasileiro.
- Histórico de produtividade.
- Possibilidade de expansão para pequenas operações logísticas.

O objetivo não é copiar a implementação do Spoke, mas construir um produto próprio, competitivo e adequado ao mercado brasileiro.

---

# 3. MÓDULOS FUNCIONAIS

O sistema será dividido em módulos independentes para facilitar a manutenção e a evolução.

## 3.1 Módulo de Dashboard

Tela inicial do aplicativo.

### Informações apresentadas

- Saudação ao usuário.
- Data atual.
- Total de rotas do dia.
- Total de pedidos.
- Entregas concluídas.
- Entregas pendentes.
- Entregas com problemas.
- Distância estimada.
- Tempo estimado.
- Progresso da rota.
- Acesso ao histórico.
- Botão para criar nova rota.

### Exemplo de informações

| Indicador | Exemplo |
|---|---:|
| Pedidos | 32 |
| Concluídos | 18 |
| Pendentes | 14 |
| Distância estimada | 56 km |
| Progresso | 56% |

Os valores acima são ilustrativos.

### Requisitos

- Atualização automática dos indicadores.
- Interface responsiva.
- Carregamento rápido.
- Acesso simplificado às funcionalidades principais.
- Persistência dos dados apresentados.

## 3.2 Módulo de gestão de pedidos

Responsável pelo cadastro, importação, edição e organização dos pedidos.

### Formas de adicionar pedidos

- Digitação manual.
- Colagem de vários endereços.
- Importação CSV.
- Importação Excel.
- Fotografias de etiquetas.
- OCR para extração de informações.
- Cadastro por voz (futuro).

### Campos de cada pedido

| Campo | Descrição |
|---|---|
| id | Identificador único |
| customer_name | Nome do destinatário |
| street | Logradouro |
| number | Número |
| complement | Complemento |
| neighborhood | Bairro |
| postal_code | CEP |
| city | Cidade |
| state | Estado |
| latitude | Latitude |
| longitude | Longitude |
| phone | Telefone opcional |
| notes | Observações |
| package_id | Identificação do pacote |
| priority | Prioridade |
| status | Situação da entrega |
| created_at | Data de criação |
| updated_at | Data de atualização |

### Status dos pedidos

- PENDING
- IN_PROGRESS
- DELIVERED
- FAILED
- SKIPPED

### Regras

- Permitir edição dos dados.
- Permitir exclusão mediante confirmação.
- Identificar endereços duplicados.
- Identificar endereços incompletos.
- Permitir correção manual.
- Preservar histórico das alterações relevantes.

---

# 4. MÓDULO DE OCR E IMPORTAÇÃO DE FOTOGRAFIAS

Um dos principais diferenciais competitivos do Rota Max.

O objetivo é permitir que o usuário fotografe etiquetas e documentos de entrega e transforme essas informações em pedidos cadastrados.

## 4.1 Tecnologia

- Google ML Kit Text Recognition.
- Flutter.
- Dart.
- Processamento local das imagens quando suportado pela implementação.

## 4.2 Fluxo de processamento

1. Usuário seleciona ou fotografa até 5 imagens.
2. Aplicativo processa as imagens.
3. OCR extrai o texto.
4. Sistema identifica possíveis nomes.
5. Sistema identifica endereços.
6. Sistema identifica números.
7. Sistema identifica CEPs.
8. Sistema identifica bairros e cidades.
9. Sistema verifica possíveis duplicidades.
10. Aplicativo apresenta os resultados.
11. Usuário confere os dados.
12. Usuário corrige informações incorretas.
13. Pedidos são salvos no SQLite.

## 4.3 Validação do OCR

O sistema deverá:

- Identificar campos incompletos.
- Identificar informações inconsistentes.
- Sinalizar baixa confiança.
- Permitir correção manual.
- Evitar cadastros duplicados.
- Nunca cadastrar automaticamente informações sem conferência do usuário.

## 4.4 Critérios de aceitação

- Processar até 5 imagens por lote.
- Exibir o resultado de cada imagem.
- Permitir editar os campos extraídos.
- Não perder os resultados em caso de erro parcial.
- Salvar os pedidos somente após confirmação.

---

# 5. MÓDULO DE OTIMIZAÇÃO DE ROTAS

Este é o principal motor de inteligência do Rota Max.

O sistema deverá encontrar uma sequência eficiente para realizar as entregas.

## 5.1 Informações necessárias

- Localização inicial.
- Lista de entregas.
- Coordenadas geográficas.
- Localização final opcional.
- Prioridade das entregas.
- Janelas de horário.
- Preferências de otimização.

## 5.2 Processo de otimização

1. Receber a lista de pedidos.
2. Validar os endereços.
3. Geocodificar os endereços.
4. Obter latitude e longitude.
5. Calcular a matriz de deslocamento.
6. Processar as possibilidades de sequência.
7. Aplicar o algoritmo de otimização.
8. Gerar a ordem recomendada.
9. Calcular distância estimada.
10. Calcular tempo estimado.
11. Apresentar o resultado ao usuário.

## 5.3 Algoritmos

### Primeira versão

Implementar:

- Nearest Neighbor (vizinho mais próximo).
- 2-opt para melhoria da sequência.

Essas heurísticas permitem desenvolver uma primeira versão sem depender de um serviço complexo de otimização.

### Evolução futura

Considerar:

- Vehicle Routing Problem (VRP).
- Vehicle Routing Problem with Time Windows (VRPTW).
- Restrições de prioridade.
- Múltiplos veículos.
- Pontos de partida e chegada.
- Restrições de capacidade.
- Otimização dinâmica.

## 5.4 Regras importantes

- Não considerar apenas distância em linha reta.
- Utilizar distâncias da malha viária sempre que disponíveis.
- Considerar sentido de deslocamento.
- Preservar entregas já concluídas.
- Permitir reotimização.
- Permitir alteração manual da sequência.
- Exibir o resultado antes de iniciar a rota.

## 5.5 Indicadores da otimização

- Distância total estimada.
- Tempo total estimado.
- Quantidade de paradas.
- Sequência recomendada.
- Distância até a próxima parada.
- Previsão de chegada.

---

# 6. MÓDULO DE MAPA E NAVEGAÇÃO

Responsável pela visualização geográfica das entregas.

## 6.1 Funcionalidades

- Mapa com todas as paradas.
- Marcadores numerados.
- Cores diferentes para cada status.
- Localização atual do usuário.
- Trajeto completo.
- Destaque da próxima parada.
- Distância até o próximo endereço.
- ETA.
- Abertura no Google Maps.
- Abertura no Waze.
- Retorno para a lista de pedidos.

## 6.2 Tecnologias

- OpenStreetMap.
- Flutter Map, conforme avaliação técnica.
- Geolocator.
- Nominatim para geocodificação, respeitando sua política de utilização.
- Serviço de roteamento compatível com a arquitetura.

## 6.3 Regras

- Solicitar permissão de localização.
- Informar quando o GPS estiver desativado.
- Atualizar a localização conforme a disponibilidade do dispositivo.
- Evitar chamadas desnecessárias aos serviços externos.
- Armazenar informações geográficas em cache.
- Preservar a rota localmente.

## 6.4 Navegação externa

O usuário poderá selecionar:

- Google Maps.
- Waze.

O aplicativo deverá abrir o endereço da próxima parada no sistema escolhido.

---

# 7. MÓDULO DE EXECUÇÃO DE ENTREGAS

Responsável pelo acompanhamento operacional da rota.

Cada parada deverá apresentar ações rápidas.

## 7.1 Ações disponíveis

| Ação | Comportamento |
|---|---|
| Entregue | Marca como concluída |
| Não entregue | Solicita motivo |
| Destinatário ausente | Registra ocorrência |
| Endereço incorreto | Registra problema |
| Pular parada | Mantém para tratamento posterior |
| Próxima parada | Avança na sequência |
| Editar | Atualiza informações |

## 7.2 Motivos de insucesso

- Destinatário ausente.
- Endereço não localizado.
- Cliente recusou.
- Local fechado.
- Problema de acesso.
- Outros.

## 7.3 Comprovante de entrega (futuro)

- Fotografia.
- Assinatura digital.
- Nome de quem recebeu.
- Data e horário.
- Geolocalização.
- Observações.

## 7.4 Requisitos

- Atualização imediata do status.
- Persistência no SQLite.
- Histórico de ocorrências.
- Recuperação da rota.
- Preservação das entregas concluídas.
- Funcionamento offline.

---

# 8. MÓDULO DE HISTÓRICO E PRODUTIVIDADE

O usuário deverá conseguir acompanhar seu desempenho.

## 8.1 Indicadores

- Total de entregas realizadas.
- Total de entregas não realizadas.
- Quilômetros percorridos.
- Tempo total de trabalho.
- Tempo médio por entrega.
- Entregas por hora.
- Consumo estimado de combustível.
- Custo estimado por quilômetro.
- Comparativo entre dias.
- Histórico de rotas.

## 8.2 Relatórios futuros

- Exportação CSV.
- Exportação PDF.
- Relatórios diários.
- Relatórios semanais.
- Relatórios mensais.
- Comparativos de produtividade.

---

# 9. ARQUITETURA TÉCNICA

## 9.1 Stack tecnológica

| Componente | Tecnologia |
|---|---|
| Linguagem | Dart |
| Framework | Flutter |
| Gerenciamento de estado | Provider |
| Banco local | SQLite |
| Persistência | SQLite + migrations |
| GPS | Geolocator |
| Mapas | OpenStreetMap |
| Geocodificação | Nominatim |
| OCR | Google ML Kit |
| Navegação externa | Google Maps / Waze |
| Armazenamento | Arquivos locais |
| Testes | Flutter Test / Integration Test |

A escolha de bibliotecas deverá ser validada conforme as versões e a compatibilidade do projeto existente.

## 9.2 Estrutura de pastas sugerida

```text
rota_max/
│
├── lib/
│   ├── main.dart
│   │
│   ├── core/
│   │   ├── constants/
│   │   ├── database/
│   │   ├── errors/
│   │   ├── services/
│   │   ├── theme/
│   │   └── utils/
│   │
│   ├── models/
│   │   ├── delivery.dart
│   │   ├── route.dart
│   │   ├── route_stop.dart
│   │   └── delivery_history.dart
│   │
│   ├── repositories/
│   │   ├── delivery_repository.dart
│   │   ├── route_repository.dart
│   │   └── history_repository.dart
│   │
│   ├── services/
│   │   ├── ocr_service.dart
│   │   ├── gps_service.dart
│   │   ├── geocoding_service.dart
│   │   ├── optimization_service.dart
│   │   └── navigation_service.dart
│   │
│   ├── providers/
│   │   ├── delivery_provider.dart
│   │   ├── route_provider.dart
│   │   └── settings_provider.dart
│   │
│   ├── features/
│   │   ├── dashboard/
│   │   ├── deliveries/
│   │   ├── import_orders/
│   │   ├── route_planner/
│   │   ├── navigation/
│   │   ├── execution/
│   │   ├── history/
│   │   └── settings/
│   │
│   └── widgets/
│
├── assets/
│   ├── images/
│   └── icons/
│
└── test/
    ├── unit/
    ├── widget/
    └── integration/
```

Esta é uma estrutura de referência. Antes de alterar o projeto, verificar a organização que já existe e preservar o código funcional.

---

# 10. BANCO DE DADOS

O Rota Max utilizará SQLite como armazenamento principal na primeira versão.

## 10.1 Tabelas

| Tabela | Responsabilidade |
|---|---|
| deliveries | Dados dos pedidos |
| routes | Informações gerais das rotas |
| route_stops | Sequência e associação das paradas |
| delivery_events | Histórico de alterações de status |
| route_history | Rotas finalizadas |
| settings | Preferências do usuário |

## 10.2 Relacionamentos

```text
ROUTES
  |
  └── ROUTE_STOPS
          |
          └── DELIVERIES

DELIVERIES
  |
  └── DELIVERY_EVENTS

ROUTES
  |
  └── ROUTE_HISTORY
```

## 10.3 Requisitos de integridade

- Identificadores únicos.
- Chaves estrangeiras.
- Índices para consultas frequentes.
- Controle de versões do banco.
- Migrations.
- Transações para operações críticas.
- Integridade dos dados após reinicialização.
- Recuperação de operações interrompidas.

## 10.4 Persistência da rota

O aplicativo deverá salvar:

- Identificação da rota.
- Lista de paradas.
- Ordem atual.
- Status de cada parada.
- Data de início.
- Data de conclusão.
- Distância estimada.
- Tempo estimado.
- Preferências de navegação.

Uma rota interrompida não poderá perder o progresso já realizado.

---

# 11. FUNCIONAMENTO OFFLINE

O funcionamento offline-first é um dos diferenciais mais importantes do Rota Max.

## 11.1 Recursos offline

O usuário deverá conseguir:

- Criar rotas.
- Consultar pedidos.
- Editar endereços.
- Marcar entregas como concluídas.
- Registrar falhas.
- Consultar histórico.
- Recuperar a última sessão.
- Continuar a operação localmente.

## 11.2 Limitações

É importante diferenciar operação offline de disponibilidade offline de mapas.

Sem internet, determinados serviços externos poderão ficar indisponíveis:

- Geocodificação online.
- Consulta de tráfego.
- Cálculo de novas rotas por provedores externos.
- Navegação online.
- Atualização de mapas.

A arquitetura deverá permitir cache de dados geográficos e avaliar mapas offline em versões futuras.

---

# 12. DIFERENCIAIS COMPETITIVOS

| Diferencial | Prioridade |
|---|---|
| OCR de até 5 fotografias por lote | Muito alta |
| Interface em português | Muito alta |
| Operação offline | Muito alta |
| Detecção de endereços duplicados | Alta |
| Reotimização durante a rota | Alta |
| Importação em lote | Alta |
| Histórico de produtividade | Alta |
| Cálculo de combustível | Média |
| Relatórios de desempenho | Média |
| Integração com WhatsApp | Futura |
| Gestão de vários entregadores | Futura |
| Painel administrativo web | Futura |

## 12.1 Principal oportunidade

O entregador brasileiro frequentemente recebe pedidos em formatos diferentes, fotografias de etiquetas e listas desorganizadas.

O Rota Max deverá tornar essa entrada de dados extremamente simples.

A combinação de OCR, validação de endereços e otimização de rotas poderá ser um dos maiores diferenciais do produto.

---

# 13. REGRAS DE NEGÓCIO

As regras abaixo deverão ser respeitadas em todos os módulos.

| Situação | Comportamento esperado |
|---|---|
| Endereço duplicado | Alertar o usuário |
| Endereço incompleto | Solicitar correção |
| GPS desativado | Solicitar ativação |
| Sem internet | Utilizar dados locais |
| OCR com baixa confiança | Solicitar conferência |
| Rota em andamento | Preservar progresso |
| Pedido concluído | Não voltar automaticamente para pendente |
| Exclusão de parada | Solicitar confirmação |
| Reotimização | Preservar entregas concluídas |
| Aplicativo fechado | Restaurar última sessão |

## 13.1 Máquina de estados

```text
PENDING
   |
   v
IN_PROGRESS
   |
   +----> DELIVERED
   |
   +----> FAILED
   |
   +----> SKIPPED
```

Uma entrega com falha ou pulada poderá ser tratada novamente.

O histórico de tentativas deverá ser preservado.

---

# 14. SEGURANÇA E PRIVACIDADE

O Rota Max poderá armazenar dados pessoais de destinatários.

Requisitos:

- Solicitar permissões de localização somente quando necessárias.
- Proteger dados armazenados.
- Evitar dados pessoais em logs.
- Permitir exclusão de dados pelo usuário.
- Implementar controle de acesso se houver login futuramente.
- Criar política de privacidade adequada à LGPD.
- Não compartilhar localização continuamente sem consentimento.
- Evitar armazenamento desnecessário de fotografias.

---

# 15. MONETIZAÇÃO

A monetização deverá ser implementada depois que a experiência principal estiver estável.

## 15.1 Modelo inicial

| Plano | Proposta |
|---|---|
| Free | Até 10 paradas por rota |
| Pro | 40 ou mais paradas e recursos avançados |
| Business | Gestão de equipes e relatórios |

Os limites são propostas iniciais e deverão ser validados comercialmente.

## 15.2 Recursos premium possíveis

- Mais paradas por rota.
- OCR avançado.
- Histórico completo.
- Relatórios.
- Reotimização avançada.
- Múltiplas rotas.
- Exportação de dados.
- Recursos empresariais.

## 15.3 Estratégia

Não implementar cobrança antes de o usuário conseguir:

1. Criar uma rota.
2. Adicionar pedidos.
3. Otimizar a sequência.
4. Navegar.
5. Concluir entregas.
6. Recuperar seu progresso.

A prioridade é entregar valor real antes de cobrar.

---

# 16. ROADMAP DE DESENVOLVIMENTO

## FASE 1 — FUNDAÇÃO

Prioridade: CRÍTICA.

- [ ] Auditar estrutura Flutter existente.
- [ ] Validar arquitetura.
- [ ] Configurar banco SQLite.
- [ ] Criar models.
- [ ] Criar repositories.
- [ ] Implementar migrations.
- [ ] Organizar navegação entre telas.
- [ ] Garantir persistência local.

## FASE 2 — GESTÃO DE PEDIDOS

- [ ] Cadastro manual.
- [ ] Edição de pedidos.
- [ ] Exclusão.
- [ ] Importação em lote.
- [ ] OCR com ML Kit.
- [ ] Validação de endereços.
- [ ] Detecção de duplicidades.
- [ ] Conferência dos dados extraídos.

## FASE 3 — MOTOR DE ROTEIRIZAÇÃO

- [ ] Geocodificação.
- [ ] Coordenadas geográficas.
- [ ] Matriz de deslocamento.
- [ ] Algoritmo Nearest Neighbor.
- [ ] Melhoria 2-opt.
- [ ] Ordenação das paradas.
- [ ] Cálculo de distância.
- [ ] Estimativa de tempo.
- [ ] Exibição da rota otimizada.

## FASE 4 — NAVEGAÇÃO

- [ ] Implementar mapa.
- [ ] Exibir marcadores.
- [ ] Implementar GPS.
- [ ] Identificar próxima parada.
- [ ] Exibir distância.
- [ ] Exibir ETA.
- [ ] Integrar Google Maps.
- [ ] Integrar Waze.

## FASE 5 — EXECUÇÃO

- [ ] Iniciar rota.
- [ ] Marcar entrega concluída.
- [ ] Registrar falhas.
- [ ] Registrar motivos.
- [ ] Pular paradas.
- [ ] Reorganizar sequência.
- [ ] Reotimizar rota.
- [ ] Recuperar sessões.
- [ ] Preservar histórico.

## FASE 6 — PRODUTIVIDADE

- [ ] Histórico.
- [ ] Estatísticas.
- [ ] Distância percorrida.
- [ ] Tempo de trabalho.
- [ ] Entregas por hora.
- [ ] Custo estimado por quilômetro.
- [ ] Relatórios.
- [ ] Exportação CSV.
- [ ] Exportação PDF.

## FASE 7 — PUBLICAÇÃO

- [ ] Testes em dispositivos reais.
- [ ] Correção de bugs.
- [ ] Revisão de permissões.
- [ ] Política de privacidade.
- [ ] Identidade visual definitiva.
- [ ] Ícone do aplicativo.
- [ ] Screenshots da Play Store.
- [ ] Preparação do Google Play.
- [ ] Publicação.
- [ ] Monitoramento de erros.

---

# 17. PLANO DE TESTES E CRITÉRIOS DE ACEITAÇÃO

Antes da publicação, o aplicativo deverá passar por testes funcionais, técnicos e operacionais.

| Cenário | Resultado esperado |
|---|---|
| 5 paradas | Otimização correta |
| 10 paradas | Sem travamentos |
| 20 paradas | Processamento estável |
| 40 paradas | Sem perda de dados |
| 5 fotografias | OCR processa todas |
| Endereços duplicados | Identificação correta |
| Sem internet | Operação local preservada |
| GPS desligado | Aviso adequado |
| Aplicativo fechado | Recuperação da rota |
| Entrega concluída | Histórico atualizado |
| Reotimização | Preserva entregas concluídas |

## 17.1 Critério principal de qualidade

Nenhuma entrega poderá desaparecer por:

- Falha de processamento.
- Fechamento do aplicativo.
- Reinicialização do dispositivo.
- Reotimização.
- Erro de gravação.
- Alteração de status.

A integridade dos dados deverá ser prioridade máxima.

---

# 18. BACKLOG INICIAL

Ver [BACKLOG.md](BACKLOG.md), que mantém o backlog vivo com o status de cada item.

---

# 19. DIRETRIZES DE DESENVOLVIMENTO

Estas regras deverão ser respeitadas por qualquer desenvolvedor ou agente de IA que trabalhar no projeto.

## 19.1 Preservação do código

- Não reconstruir funcionalidades que já existem sem necessidade.
- Não apagar arquivos funcionais sem justificativa.
- Não substituir tecnologias sem avaliar impactos.
- Não modificar estruturas do banco sem migrations.
- Não quebrar funcionalidades existentes para implementar novas.

## 19.2 Organização

- Manter separação entre interface e regras de negócio.
- Utilizar repositories para acesso aos dados.
- Utilizar services para integrações e operações específicas.
- Utilizar providers para gerenciamento de estado.
- Evitar duplicação de código.
- Criar componentes reutilizáveis.

## 19.3 Qualidade

- Implementar tratamento de erros.
- Criar testes unitários.
- Criar testes de widgets.
- Criar testes de integração.
- Documentar decisões técnicas.
- Validar o comportamento offline.
- Verificar desempenho com 40 paradas.

## 19.4 Desenvolvimento assistido por IA

Ao utilizar Claude Code, VS Code ou outro agente:

1. Primeiro analisar os arquivos existentes.
2. Identificar o contexto da funcionalidade.
3. Apresentar um plano de implementação.
4. Alterar somente os arquivos necessários.
5. Executar testes.
6. Corrigir problemas identificados.
7. Atualizar a documentação.
8. Registrar o que foi concluído.

O agente não deverá afirmar que uma funcionalidade está pronta sem verificar sua implementação.

---

# 20. AUDITORIA DO PROJETO EXISTENTE

Realizada em 08/11/2026. Ver [AUDIT.md](AUDIT.md).

---

# 21. VISÃO DE FUTURO

O Rota Max deverá evoluir de um simples planejador de rotas para uma plataforma completa de produtividade logística.

Possíveis expansões:

- Sincronização em nuvem.
- Login e autenticação.
- Aplicativo para equipes.
- Painel administrativo web.
- Gestão de múltiplos entregadores.
- Distribuição de pedidos.
- Integração com marketplaces.
- Integração com transportadoras.
- Inteligência artificial para leitura de pedidos.
- Previsão de tempo de entrega.
- Relatórios empresariais.
- Gestão de frota.

Essas funcionalidades não fazem parte da primeira versão obrigatória.

A prioridade é construir uma base sólida e entregar uma excelente experiência individual de roteirização.

---

# 22. IDENTIDADE DO PRODUTO

**Nome:** Rota Max

**Slogan:** Sua rota. Seu controle. Seu resultado.

**Categoria:** Tecnologia para entregas e logística.

**Proposta de valor:** Organizar, otimizar e acompanhar entregas em um único aplicativo.

**Pilares do produto:**

1. Simplicidade.
2. Velocidade.
3. Inteligência.
4. Confiabilidade.
5. Produtividade.
6. Independência operacional.

**Objetivo final:**

Construir um aplicativo profissional, estável e competitivo, que permita ao entregador economizar tempo, reduzir deslocamentos desnecessários e realizar mais entregas com organização.

---

**ROTA MAX — Documento Mestre do Produto**

Versão: 1.0  
Status: Escopo inicial definido  
Plataforma: Flutter / Android  
Banco de dados: SQLite  
Modelo: Offline-first

**Princípio de desenvolvimento:**

Não desenvolver funcionalidades apenas para aumentar a quantidade de recursos. Cada funcionalidade deverá resolver um problema real do entregador e contribuir para uma operação mais rápida, simples e eficiente.
