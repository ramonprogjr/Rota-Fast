# Arquitetura

O Rota Pizza é um app Flutter offline-first. Não há servidor próprio.

```
UI (telas / Provider)
        |
        v
Repositórios  ---- SQLite (entregas, pizzaria, cache, ajustes)
        |
        +--> Nominatim (geocodificação, 1 req/s + cache)
        +--> RouteOptimizer (Haversine + nearest neighbor)
        +--> MapsService (intent / URL do Google Maps)
        +--> LocationService (GPS opcional)
```

## Camadas

- **UI:** splash, home, cadastro, detalhe, colar lote, histórico, pizzaria
- **Estado:** `AppState` (Provider)
- **Domínio:** `Delivery`, `Pizzeria`, `RouteOptimizer`
- **Dados:** SQLite via `sqflite`
- **Integrações:** Nominatim HTTP, `url_launcher`, `geolocator`

## Rota

Origem = pizzaria (ou GPS, se autorizado). Entre as pendentes com coordenada, escolhe a de menor distância ponderada pela prioridade (urgente 0,4 / alta 0,7 / normal 1,0). Entregas sem coordenada vão para o fim da lista.

Tempo estimado = km em linha reta / 28 km/h.

## Privacidade

Cliente, endereço, telefone e valor ficam só no aparelho. A consulta ao Nominatim envia o texto do endereço para o serviço público do OpenStreetMap.
