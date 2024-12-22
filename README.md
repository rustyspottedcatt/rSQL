# I'm too lazy to finish this module so if u want to finish it u can go ahead
# EconomyServer Module for Roblox

## Overview
The EconomyServer module is a comprehensive Lua script designed for Roblox developers to easily create, manage, and convert virtual currencies within their games. It offers robust features such as currency creation, inflation rate handling, currency conversion, and real-time balance updates.

## Features
- **Currency Creation**: Define your own virtual currencies with custom names, symbols, initial distribution amounts, and optional inflation rates.
- **Dynamic Currency Management**: Track and update currency balances for players, handle earned and spent events, and adjust for inflation dynamically.
- **Currency Conversion**: Convert amounts between different currencies based on specified exchange rates, allowing for complex economic interactions within your game.

## Getting Started
To integrate the EconomyServer module into your game, follow these steps:
1. Place the EconomyServer script in a ServerScriptService or a similar server-side location.
2. Require the module in your game scripts where you need to manage virtual currencies.

```lua
local Economy = require(game.ServerScriptService.RoEconomy)
```

## Creating a Currency
Use the CreateCurrency method to define a new virtual currency. Specify the currency's name, symbol, initial distribution, and optionally, an inflation rate.

```lua
local USD = Economy:CreateCurrency("USD", "$", 1000, 0.2)
```

## Managing Currencies

GetCurrency: Retrieve details of a specific currency by its name.
ConvertCurrency: Convert a specified amount from one currency to another, adjusting for exchange rates.

## Example Usage

```lua
-- Creating a new currency
local Gold = Economy:CreateCurrency("Gold", "G", 5000)

-- Converting currency for a player
Economy:ConvertCurrency(player, 100, Gold, USD)

```

## Contributions
This module is open for contributions. Please adhere to the guidelines under the MIT License for modifications and redistributions.

## License
This project is licensed under the MIT License - see the LICENSE file for details.
