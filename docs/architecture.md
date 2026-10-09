# Arquitetura do produto

## Visão atual

O projeto atual é um app Flutter offline-first para entregas locais. Ele resolve bem a jornada do entregador individual: cadastrar endereços, localizar no mapa, otimizar a rota, registrar km, e enviar relatório do dia.

A arquitetura atual é forte para um MVP, mas precisa evoluir para um sistema multiusuário, com backend, autenticação, gestão de equipes e dados operacionais em nuvem.

```
Cliente mobile (Flutter)
        |
        v
UI + Provider / State
        |
        v
Camada de domínio
  - Delivery
  - Shift
  - RouteOptimizer
  - GeocodingService
  - ShiftTracker
        |
        v
Persistência local
  - SQLite
  - cache de geocodificação
  - histórico do turno
        |
        v
Serviços externos
  - Nominatim / OpenStreetMap
  - Google Maps
  - GPS / geolocator
  - OCR local
```

## Camadas do MVP atual

- **UI:** telas de cadastro, histórico, rota, relatório, ajuste de endereço
- **Estado:** AppState centraliza regras de negócio e navegação
- **Domínio:** entregas, turno, origem, prioridade, histórico e cálculo de rota
- **Dados locais:** SQLite com repositorios dedicados
- **Integrações:** geocodificação, mapas, GPS, OCR e WhatsApp

## Estrutura funcional atual

- Origem = pizzaria ou ponto de saída do entregador
- Rota organizada por menor distância ponderada pela prioridade
- Entregas sem coordenada vão para o fim da lista
- Tempo estimado simples em linha reta
- Relatório do turno salva dados no celular
- OCR e paradas em lote resolvem parte do volume de operação

## Limitações do MVP

O produto atual ainda é centrado no dispositivo individual. Ele não escala para:

- múltiplos usuários e empresas
- gestão de entregadores
- painel administrativo
- sincronização em tempo real
- relatórios de produtividade por equipe
- roteirização com dados de trânsito e janela de entrega
- IA de logística e análise operacional

## Arquitetura alvo do Rota Max

A próxima etapa deve sair do modelo local e passar para um sistema de plataforma.

```
Flutter app (entregador / operação)
        |
        v
API Backend
  - Auth
  - Users / Companies
  - Drivers / Teams
  - Orders / Deliveries
  - Routing engine
  - Reports / Analytics
        |
        +---------------------------+
        |                           |
        v                           v
Banco relacional / cache      Dashboard web / admin
PostgreSQL / Supabase / Firebase
Redis / queue para jobs
```

## Módulos propostos para a plataforma

### 1. Core operacional
- autenticação de usuários
- cadastro de empresas e entregadores
- perfis e permissões
- gestão de veículos e turnos

### 2. Entregas e pedidos
- importação em lote
- validação de endereços
- associação com clientes e ordens
- prioridade, status e SLA

### 3. Roteirização
- algoritmo de otimização com múltiplos critérios
- origem por ponto de coleta ou sede
- agrupamento por região e zona
- prevenção de cruzamento desnecessário
- cálculo com mapas reais e trânsito

### 4. Monitoramento
- status ao vivo das entregas
- tempo de rota
- atraso e alerta
- histórico por turno e por motorista

### 5. Gestão e produtividade
- KPIs por entregador
- comparativo de performance
- custo por entrega
- faturamento, quilometragem e tempo

### 6. IA e decisão operacional
- sugestão de melhor sequência
- previsão de atraso
- identificação de regiões de maior volume
- recomendação de organização por jornada

## Privacidade e compliance

A base atual já respeita o princípio de dados locais. A evolução do Rota Max precisa manter:

- dados de clientes em ambiente seguro
- consentimento e controle de acesso
- logs de operação e auditoria
- proteção de telecom no transporte de informações
- visão clara de responsabilidade entre empresa e entregador

## Conclusão

O MVP atual resolve bem a execução individual. O caminho para o Rota Max é transformar esse app em uma plataforma de logística operacional, com backend, gestão de equipe e dados em nuvem, sem perder a simplicidade e a experiência de uso que já funcionam no campo.
