# Backlog — Rota Max

Legenda: ✅ pronto · 🟡 parcial · ⬜ a fazer · ⏭️ fora da v1.0

Recorte da **v1.0** (primeira publicação, teste fechado com motoristas parceiros): base + execução. Status inicial vem da [auditoria](AUDIT.md) de 08/11/2026.

## Etapa 0 — Documentação e auditoria
- ✅ PRD, auditoria, arquitetura, banco e backlog em `docs/`
- ✅ Documentos antigos do Rota Food movidos para `docs/archive/`

## Etapa 1 — Rebrand e limpeza
- ✅ Pacote `rota_pizza` → `rota_max`; `RotaPizzaApp` → `RotaMaxApp`; `Pizzeria` → `BaseLocation` ("ponto de saída")
- ✅ applicationId `com.rotamax.app`, nome "Rota Max", textos sem "pizza"/"Rota Food"
- ✅ Cidade padrão vinda do ponto de saída
- ✅ Ícone provisório "RM" (arte definitiva a fornecer)
- ✅ Remover dados de demonstração do app (bug crítico)
- ✅ Remover Supabase e código de plataforma não usado; `supabase/` vira referência (RLS corrigido)

## Etapa 2 — Fundação do banco (PRD §10)
- ⬜ `rota_max.db` versão 1 com executor de migrations, FKs e índices
- ⬜ Campos `postal_code`, `state`, `notes`, `package_id`, `updated_at`
- ⬜ Tabelas `routes`, `route_stops`, `delivery_events`
- ⬜ Status PENDING / IN_PROGRESS / DELIVERED / FAILED / SKIPPED e motivos de insucesso
- ⬜ Toda troca de status transacional e com evento gravado

## Etapa 3 — Execução e recuperação (PRD §7, §13)
- ✅ Marcar entregue · ✅ Editar · ✅ Excluir com confirmação
- ⬜ Não entregue com motivo · ⬜ Pular · ⬜ Tentar de novo
- ⬜ Próxima parada em andamento; recuperação da rota após fechar o app

## Etapa 4 — Roteirização (PRD §5)
- ✅ Vizinho mais próximo com prioridade · ✅ Reotimização preservando concluídas
- ⬜ 2-opt · ⬜ Reordenação manual · ⬜ Tela de revisão antes de iniciar
- ⬜ Fator de malha viária na estimativa · ⏭️ Distância real por roteador (OSRM)

## Etapa 5 — Mapa e navegação (PRD §6)
- ✅ Google Maps · ⬜ Waze · ⬜ Escolha do app de navegação
- ⬜ Mapa das paradas com marcadores numerados por status e posição atual
- ⬜ Aviso de GPS desligado

## Etapa 6 — Pedidos, OCR e geocodificação
- ✅ Cadastro manual · ✅ Colar endereços · ✅ OCR 5 fotos com conferência
- ⬜ Ler cache de geocodificação · ⬜ CEP, bairro e UF no parser
- ⬜ Selo de baixa confiança · ⬜ Não descartar entrega com geocode falho
- ⬜ Localizar em lote após colar · ⬜ Duplicidade por CEP + número
- ⏭️ Importação CSV / Excel

## Etapa 7 — Dashboard e histórico (PRD §3.1, §8)
- ✅ Painel pessoal com indicadores reais (sem tendências inventadas)
- ✅ Relatório do turno · ⬜ Entregas/hora, falhas, custo por km no histórico
- ⏭️ Exportação CSV / PDF

## Etapa 8 — Play Store (PRD §16 Fase 7)
- ⬜ Assinatura de release e `.aab` · ✅ Versão 1.0.0+1
- ⬜ Política de privacidade (LGPD) · ⬜ Ficha da loja e formulário de segurança de dados
- ⬜ Justificativa de localização em segundo plano · ⬜ Apagar todos os dados
- ✅ CI com versão do Flutter fixa (3.47.9)
- ⬜ Testes do PRD §17 em celular real

## Depois da v1.0
- ⏭️ Janelas de horário, pausas, ponto de chegada
- ⏭️ Comprovante de entrega (foto, assinatura)
- ⏭️ Monetização (Free / Pro / Business)
- ⏭️ Sincronização em nuvem, login e gestão de equipes (ver `supabase/`)
