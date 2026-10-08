# Requisitos — Rota Pizza 1.0

## Funcionais

- RF01 Cadastrar entrega (cliente, pedido, endereço, telefone, valor, prioridade)
- RF02 Editar entrega
- RF03 Excluir entrega
- RF04 Pesquisar/localizar endereço (Nominatim)
- RF05 Obter e armazenar coordenadas
- RF06 Calcular sequência (vizinho mais próximo + prioridade)
- RF07 Exibir rota, distância e tempo estimados
- RF08 Abrir Google Maps com o destino
- RF09 Marcar entrega como concluída
- RF10 Recalcular rota (manual e após concluir)
- RF11 Armazenar histórico local do turno
- RF12 Funcionar sem anúncios e sem conta
- RF13 Cadastrar pizzaria (ponto de partida)
- RF14 Colar vários endereços de uma vez
- RF15 Abrir WhatsApp e discador quando houver telefone

## Não funcionais

- RNF01 Aplicativo Android (APK)
- RNF02 Interface com alvos grandes e alto contraste (modo escuro)
- RNF03 Dados apenas no SQLite local
- RNF04 Comunicação HTTPS com Nominatim
- RNF05 Funções básicas offline (lista, editar, concluir)
- RNF06 Sem backend e sem login no MVP
