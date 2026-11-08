# Backlog — Rota Max

Legenda: ✅ pronto · 🟡 parcial · ⬜ a fazer · ⏭️ fora da v1.0

Foco da **v1.0**: app de entregas, roteirização e trajetos para **motoristas parceiros** (moto, carro, utilitário, van, caminhão leve). Primeira publicação em teste fechado na Play Store. Status inicial vem da [auditoria](AUDIT.md) de 08/11/2026.

## Etapa 0 — Documentação e auditoria
- ✅ PRD, auditoria, arquitetura, banco e backlog em `docs/`

## Etapa 1 — Rebrand e limpeza
- ✅ Pacote `rota_max`, applicationId `com.rotamax.app`, nome "Rota Max"
- ✅ Sem demo em produção, sem Supabase no app, cidade vinda do ponto de saída
- ✅ Painel do dia com números reais · ✅ CI com Flutter 3.47.9 · ✅ Versão 1.0.0+1

## Etapa 2 — Fundação do banco (PRD §10)
- ✅ Migrations, FKs, índices e CHECKs
- ✅ Status PENDING / IN_PROGRESS / DELIVERED / FAILED / SKIPPED, motivos, tentativas
- ✅ `routes`, `route_stops`, `delivery_events`, `route_plans`, `vehicles`, `oil_changes`
- ✅ Troca de status transacional com evento · ✅ Testes no SQLite real e em memória

## Etapa 3 — Identidade visual "Azul logística"
- ✅ Paleta nova, cores por status, ícone e splash
- ✅ Barra inferior: Rota · Relatórios · Veículos · Ajustes (Relatórios e Veículos provisórios até as Etapas 6 e 8)

## Etapa 4 — Execução (PRD §7, §13)
- ✅ Regras no banco · ⬜ Botões Não entregue (motivo), Pular, Tentar de novo
- ⬜ Card "Próxima parada" · ⬜ Linha do tempo de eventos da entrega

## Etapa 5 — Roteirização e economia (PRD §5)
- ✅ Vizinho mais próximo com prioridade · ⬜ 2-opt · ⬜ Fator de malha viária
- ⬜ Velocidade do veículo ativo · ⬜ Linha de base (ordem de cadastro) e economia
- ⬜ Reordenação manual · ⬜ Tela "Rota pronta"

## Etapa 6 — Veículos e manutenção
- ⬜ Vários veículos, um ativo, padrões por tipo
- ⬜ Km do turno no odômetro do veículo · ⬜ Aviso e histórico de troca de óleo

## Etapa 7 — Mapa, navegação e postos (PRD §6)
- ⬜ Mapa das paradas · ✅ Google Maps · ⬜ Waze · ⬜ Aviso de GPS desligado
- ⬜ Postos de combustível por perto (OpenStreetMap)

## Etapa 8 — Relatórios (PRD §8)
- ⬜ Tempo, km e R$ economizados por dia/semana/mês
- ⬜ Entregas, falhas, taxa de sucesso, km GPS, entregas/hora, custo por km

## Etapa 9 — Pedidos, OCR e geocodificação
- ✅ Cadastro · ✅ Colar endereços · ✅ OCR 5 fotos com conferência
- ⬜ Cache de geocodificação lido · ⬜ CEP/UF/bairro · ⬜ Baixa confiança
- ⬜ Não descartar entrega sem localização · ⏭️ CSV / Excel

## Etapa 10 — Play Store
- ⬜ Assinatura e `.aab` · ⬜ Política de privacidade · ⬜ Ficha e segurança de dados
- ⬜ Justificativa de localização em segundo plano · ⬜ Apagar todos os dados
- ⬜ Testes do PRD §17 em celular real

## Depois da v1.0
- ⏭️ Malha viária real (OSRM), janelas de horário, comprovante de entrega
- ⏭️ Preço de combustível (ANP), notificação de troca de óleo, exportar PDF/CSV
- ⏭️ Monetização, sincronização em nuvem e equipes (ver `supabase/`)
