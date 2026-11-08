# Rota Max — Documento de Requisitos Funcionais

**Versão:** 1.0  
**Prioridade estratégica:** Otimização de rotas  
**Plataforma inicial:** Android  
**Tecnologia prevista:** Flutter / Dart  
**Público-alvo:** Entregadores autônomos e profissionais de logística.

A situação de cada requisito no código está em [GAP_ANALYSIS.md](GAP_ANALYSIS.md).

---

## 1. Objetivo do produto

Desenvolver um aplicativo de roteirização que organize entregas de maneira inteligente, confiável e simples de operar.

O Rota Max deverá resolver seis problemas identificados durante o uso do Spoke:

1. Otimização que gera trajetos desnecessários.
2. Dificuldade para editar a sequência das paradas.
3. Endereços e localizações incorretos.
4. Travamentos e encerramentos inesperados.
5. Perda de endereços e rotas.
6. Falhas ou demora na localização GPS.

**Regra principal do produto:** o entregador deve ter confiança de que a rota calculada faz sentido, pode ser ajustada manualmente e não será perdida durante a operação.

---

# 2. Requisitos funcionais

## RF-001 — Otimização inteligente de rotas
**Prioridade: P0 — Crítica**

O sistema deverá calcular a melhor sequência possível de entregas considerando a malha viária, a distância e o tempo estimado de deslocamento.

- Definir ponto inicial da rota.
- Definir ponto final, quando necessário.
- Organizar automaticamente as paradas.
- Considerar ruas, avenidas, mão única e restrições de circulação disponíveis no provedor de mapas.
- Evitar retornos desnecessários.
- Evitar cruzamentos repetidos entre bairros.
- Reduzir deslocamentos e distância total.
- Exibir distância total estimada.
- Exibir tempo estimado da rota.
- Permitir recalcular a rota.
- Preservar entregas já concluídas durante a reotimização.

## RF-002 — Edição manual da sequência
**Prioridade: P1 — Alta**

- Arrastar e soltar paradas para alterar a ordem.
- Mover uma parada para cima ou para baixo.
- Fixar uma entrega em determinada posição.
- Bloquear uma parada para que a otimização não a mova.
- Recalcular o trajeto após alterações.
- Desfazer alterações recentes.
- Visualizar a numeração atualizada das paradas.

## RF-003 — Validação e precisão dos endereços
**Prioridade: P0 — Crítica**

- Pesquisar endereços.
- Sugerir endereços durante a digitação.
- Identificar endereços incompletos.
- Exibir endereço encontrado no mapa.
- Permitir ajuste manual do pino de localização.
- Permitir editar número, complemento, CEP e referência.
- Alertar quando não for possível localizar um endereço.
- Identificar possíveis endereços duplicados.

## RF-004 — Estabilidade e recuperação de sessão
**Prioridade: P0 — Crítica**

- Salvar alterações automaticamente.
- Persistir dados localmente.
- Recuperar a última rota aberta.
- Recuperar a sequência das paradas.
- Preservar o status das entregas.
- Recuperar informações após reinicialização do aparelho.
- Evitar duplicidade de registros durante gravações.
- Informar ao usuário quando ocorrer uma falha que impeça alguma operação.

## RF-005 — Persistência de endereços e rotas
**Prioridade: P0 — Crítica**

- Salvar rotas automaticamente.
- Salvar cada entrega individualmente.
- Manter histórico de rotas.
- Permitir abrir rotas anteriores.
- Permitir editar entregas pendentes.
- Preservar dados mesmo sem conexão com a internet.
- Manter o histórico de alterações e tentativas de entrega.

## RF-006 — GPS e localização
**Prioridade: P1 — Alta**

- Solicitar permissões de localização.
- Identificar quando o GPS estiver desativado.
- Exibir a localização atual no mapa.
- Atualizar a posição durante a execução da rota.
- Informar quando o sinal estiver indisponível.
- Exibir a última localização conhecida.
- Permitir tentar obter a localização novamente.
- Não impedir o acesso aos dados da rota quando o GPS falhar.

---

# 3. Histórias de usuário e critérios de aceitação

## HU-001 — Calcular uma rota eficiente
**Como** entregador, **quero** que o aplicativo organize minhas entregas considerando as ruas reais, **para** percorrer a menor distância ou o menor tempo possível.

- [ ] Com vários endereços cadastrados, ao solicitar a otimização, o sistema calcula uma sequência de paradas.
- [ ] O cálculo considera os trajetos da malha viária, e não apenas linha reta.
- [ ] O sistema respeita restrições de circulação conhecidas pelo provedor de rotas.
- [ ] Apresenta a distância total estimada.
- [ ] Apresenta o tempo estimado.
- [ ] Não cria deslocamentos desnecessários quando há alternativa viável melhor.
- [ ] Informa quando algum endereço não pode ser roteado.
- [ ] Se o cálculo falhar, a sequência original é preservada.

**Teste de referência:** 20 entregas em ruas e bairros diferentes; comparar a rota com alternativas e verificar retornos, cruzamentos e distância total.

## HU-002 — Alterar a ordem das entregas
- [ ] Arrastar uma entrega altera sua posição.
- [ ] A numeração é atualizada automaticamente.
- [ ] A alteração é salva e continua salva após fechar e abrir o app.
- [ ] É possível recalcular a rota após a edição.
- [ ] Entregas concluídas não são reposicionadas automaticamente.
- [ ] É possível desfazer uma alteração recente.

## HU-003 — Corrigir um endereço
- [ ] Apresenta o endereço identificado e o ponto no mapa.
- [ ] Permite ajustar manualmente a localização.
- [ ] Sinaliza endereços não encontrados.
- [ ] Permite editar o endereço antes de iniciar a rota.
- [ ] Endereços duplicados geram alerta, sem exclusão automática.

## HU-004 — Recuperar uma rota após fechamento inesperado
- [ ] Cada alteração importante é persistida localmente.
- [ ] O app recupera a última sessão válida, com concluídas, pendentes e a sequência.
- [ ] A recuperação não cria entregas duplicadas.
- [ ] Os dados locais continuam acessíveis sem internet.

## HU-005 — Manter os dados das rotas
- [ ] Toda rota criada é salva, e toda entrega tem registro persistente.
- [ ] O histórico permite consultar rotas anteriores.
- [ ] Os dados continuam disponíveis após reiniciar o aparelho.
- [ ] Excluir uma rota exige confirmação e não apaga outras rotas.

## HU-006 — Acompanhar minha localização
- [ ] Solicita a permissão de localização.
- [ ] Identifica quando o GPS está desativado.
- [ ] Atualiza a posição conforme os dados disponíveis.
- [ ] Informa quando não consegue obter posição atualizada.
- [ ] A última localização conhecida pode ser exibida, identificada como desatualizada.
- [ ] A falha do GPS não apaga nem invalida a rota salva.

---

# 4. Requisitos não funcionais

| ID | Requisito | Critério |
|---|---|---|
| RNF-001 | Persistência | Dados importantes salvos em banco local SQLite |
| RNF-002 | Offline-first | Cadastro, edição e consulta disponíveis sem internet |
| RNF-003 | Recuperação | Retomar a última sessão válida |
| RNF-004 | Desempenho | Evitar bloqueio da interface durante cálculos |
| RNF-005 | Estabilidade | Tratar erros sem encerrar o aplicativo |
| RNF-006 | Integridade | Evitar duplicidade e perda de registros |
| RNF-007 | Usabilidade | Edição de paradas simples e intuitiva |
| RNF-008 | Testabilidade | Testes unitários, integração e testes de interface |

---

# 5. Estratégia técnica para a otimização

1. Receber os endereços cadastrados.
2. Validar e geocodificar cada endereço.
3. Identificar coordenadas válidas.
4. Consultar distâncias e tempos pela malha viária.
5. Construir uma matriz de deslocamento entre as paradas.
6. Calcular uma sequência inicial.
7. Aplicar melhorias na sequência.
8. Validar o resultado.
9. Exibir a rota no mapa.

| Etapa | Estratégia |
|---|---|
| MVP | Nearest Neighbor + 2-opt |
| Evolução | Matriz de tempo e distância da malha viária |
| Avançado | Otimização com restrições e janelas de horário |
| Futuro | VRP e VRPTW para múltiplos veículos e restrições |

Nearest Neighbor e 2-opt são heurísticas: não garantem a melhor rota global. O Rota Max deve comparar resultados com cenários de referência antes de considerar o motor confiável.

**Decisões de implementação (08/11/2026):** matriz de tempo e distância do **OpenRouteService** (perfis carro e caminhão), chave via `--dart-define=ORS_API_KEY`; sem chave, sem rede ou com falha, cálculo local (linha reta × 1,3) com aviso e ordem atual preservada. Autocompletar de endereço também pelo OpenRouteService.

---

# 6. Plano de testes prioritários

| Teste | Cenário | Resultado esperado |
|---|---|---|
| QA-001 | Rota com 5 paradas | Sequência calculada corretamente |
| QA-002 | Rota com 10 paradas | Sem retornos evitáveis |
| QA-003 | Rota com 20 paradas | Deslocamento coerente entre bairros |
| QA-004 | Rota com 40 paradas | Cálculo concluído sem travar a interface |
| QA-005 | Reorganizar paradas | Nova ordem salva corretamente |
| QA-006 | Endereço inválido | Sistema alerta e permite correção |
| QA-007 | Endereço duplicado | Sistema identifica possível duplicidade |
| QA-008 | Fechar aplicativo durante a rota | Recuperação da sessão |
| QA-009 | Reiniciar o aparelho | Dados preservados |
| QA-010 | Desativar GPS | Aviso apresentado, rota preservada |
| QA-011 | Desativar internet | Dados locais continuam acessíveis |
| QA-012 | Reotimizar rota em andamento | Entregas concluídas preservadas |

# 7. Ordem de desenvolvimento

| Ordem | Entrega | Prioridade |
|---|---|---|
| 1 | Motor de otimização e matriz de deslocamento | P0 |
| 2 | Validação e geolocalização dos endereços | P0 |
| 3 | Persistência e recuperação de rotas | P0 |
| 4 | Edição manual da sequência | P1 |
| 5 | GPS e acompanhamento da rota | P1 |
| 6 | Histórico e produtividade | P2 |
| 7 | Recursos avançados e monetização | Futuro |

# 8. Definição de pronto

Uma funcionalidade só está concluída quando: está implementada; trata erros; tem testes; não causa regressões; persiste os dados necessários; funciona nos cenários offline previstos; tem documentação técnica atualizada; **foi validada em aparelho Android real**.

# 9. Indicadores de qualidade

- Distância total planejada versus distância percorrida.
- Quantidade de retornos e trechos repetidos.
- Tempo necessário para calcular uma rota.
- Percentual de endereços geocodificados corretamente.
- Taxa de falhas durante a otimização.
- Quantidade de sessões recuperadas com sucesso.
- Quantidade de travamentos e encerramentos inesperados.

**Meta:** rota consistente, editável e confiável, sem prometer uma rota matematicamente perfeita em todos os cenários.
