# Plano de testes

## Testes automatizados

- Haversine e formatação de distância/tempo
- Vizinho mais próximo e viés de prioridade
- Parser de endereços (linha única e lote)
- Normalização de telefone para WhatsApp
- Widget: splash, cadastrar entrega, marcar entregue

## Testes manuais

**TC-001 — Cadastrar entrega**  
Dado que estou na tela inicial, quando adiciono um endereço válido, então a entrega aparece na lista.

**TC-002 — Endereço inválido**  
Dado que informo um endereço inexistente, quando toco em localizar, então o sistema informa que o endereço não foi encontrado.

**TC-003 — Navegação**  
Dado que existe uma entrega válida, quando toco em Navegar, então o Google Maps abre com o destino.

**TC-004 — Entrega concluída**  
Dado que existe uma entrega pendente, quando marco como entregue, então o status muda para concluído.

**TC-005 — Colar lote**  
Dado um texto com várias linhas, quando importo, então cada linha vira uma entrega.

**TC-006 — Offline**  
Dado que não há internet, quando abro o app, então a lista já salva continua visível e posso marcar entregue.
