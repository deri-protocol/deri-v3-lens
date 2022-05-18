// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './utils/NameVersion.sol';
import './library/SafeMath.sol';
import './SymbolsLens.sol';

contract DeriLens is NameVersion {

    using SafeMath for uint256;
    using SafeMath for int256;

    int256 constant ONE = 1e18;

    ISymbolsLens immutable symbolsLens;

    constructor (address symbolsLens_) NameVersion('DeriLens', '3.0.2') {
        symbolsLens = ISymbolsLens(symbolsLens_);
    }

    struct PoolInfo {
        address pool;
        address implementation;
        address protocolFeeCollector;

        address tokenB0;
        address tokenWETH;
        address vTokenB0;
        address vTokenETH;
        address lToken;
        address pToken;
        address oracleManager;
        address swapper;
        address symbolManager;
        uint256 reserveRatioB0;
        int256 minRatioB0;
        int256 poolInitialMarginMultiplier;
        int256 protocolFeeCollectRatio;
        int256 minLiquidationReward;
        int256 maxLiquidationReward;
        int256 liquidationRewardCutRatio;

        int256 liquidity;
        int256 lpsPnl;
        int256 cumulativePnlPerLiquidity;
        int256 protocolFeeAccrued;

        address symbolManagerImplementation;
        int256 initialMarginRequired;
    }

    struct MarketInfo {
        address underlying;
        address vToken;
        string underlyingSymbol;
        string vTokenSymbol;
        uint256 underlyingPrice;
        uint256 exchangeRate;
        uint256 vTokenBalance;
    }

    struct LpInfo {
        address account;
        uint256 lTokenId;
        address vault;
        int256 amountB0;
        int256 liquidity;
        int256 cumulativePnlPerLiquidity;
        uint256 vaultLiquidity;
        MarketInfo[] markets;
    }

    struct PositionInfo {
        address symbolAddress;
        string symbol;
        int256 volume;
        int256 cost;
        int256 cumulativeFundingPerVolume;
    }

    struct TdInfo {
        address account;
        uint256 pTokenId;
        address vault;
        int256 amountB0;
        uint256 vaultLiquidity;
        MarketInfo[] markets;
        PositionInfo[] positions;
    }

    function getInfo(address pool_, address account_, ISymbolsLens.PriceAndVolatility[] memory pvs) external view returns (
        PoolInfo memory poolInfo,
        MarketInfo[] memory marketsInfo,
        ISymbolsLens.SymbolInfo[] memory symbolsInfo,
        LpInfo memory lpInfo,
        TdInfo memory tdInfo
    ) {
        poolInfo = getPoolInfo(pool_);
        marketsInfo = getMarketsInfo(pool_);
        symbolsInfo = getSymbolsInfo(pool_, pvs);
        lpInfo = getLpInfo(pool_, account_);
        tdInfo = getTdInfo(pool_, account_);
    }

    function getPoolInfo(address pool_) public view returns (PoolInfo memory info) {
        ILensPool p = ILensPool(pool_);
        info.pool = pool_;
        info.implementation = p.implementation();
        info.protocolFeeCollector = p.protocolFeeCollector();
        info.tokenB0 = p.tokenB0();
        info.tokenWETH = p.tokenWETH();
        info.vTokenB0 = p.vTokenB0();
        info.vTokenETH = p.vTokenETH();
        info.lToken = p.lToken();
        info.pToken = p.pToken();
        info.oracleManager = p.oracleManager();
        info.swapper = p.swapper();
        info.symbolManager = p.symbolManager();
        info.reserveRatioB0 = p.reserveRatioB0();
        info.minRatioB0 = p.minRatioB0();
        info.poolInitialMarginMultiplier = p.poolInitialMarginMultiplier();
        info.protocolFeeCollectRatio = p.protocolFeeCollectRatio();
        info.minLiquidationReward = p.minLiquidationReward();
        info.maxLiquidationReward = p.maxLiquidationReward();
        info.liquidationRewardCutRatio = p.liquidationRewardCutRatio();
        info.liquidity = p.liquidity();
        info.lpsPnl = p.lpsPnl();
        info.cumulativePnlPerLiquidity = p.cumulativePnlPerLiquidity();
        info.protocolFeeAccrued = p.protocolFeeAccrued();

        info.symbolManagerImplementation = ILensSymbolManager(info.symbolManager).implementation();
        info.initialMarginRequired = ILensSymbolManager(info.symbolManager).initialMarginRequired();
    }

    function getMarketsInfo(address pool_) public view returns (MarketInfo[] memory infos) {
        ILensPool pool = ILensPool(pool_);
        ILensComptroller comptroller = ILensComptroller(ILensVault(pool.vaultImplementation()).comptroller());
        ILensOracle oracle = ILensOracle(comptroller.oracle());

        address tokenB0 = pool.tokenB0();
        address tokenWETH = pool.tokenWETH();
        address vTokenB0 = pool.vTokenB0();
        address vTokenETH = pool.vTokenETH();

        address[] memory allMarkets = comptroller.getAllMarkets();
        address[] memory underlyings = new address[](allMarkets.length);
        uint256 count;
        for (uint256 i = 0; i < allMarkets.length; i++) {
            address vToken = allMarkets[i];
            if (vToken == vTokenB0) {
                underlyings[i] = tokenB0;
                count++;
            } else if (vToken == vTokenETH) {
                underlyings[i] = tokenWETH;
                count++;
            } else {
                address underlying = ILensVToken(vToken).underlying();
                if (pool.markets(underlying) == vToken) {
                    underlyings[i] = underlying;
                    count++;
                }
            }
        }

        infos = new MarketInfo[](count);
        count = 0;
        for (uint256 i = 0; i < underlyings.length; i++) {
            if (underlyings[i] != address(0)) {
                infos[count].underlying = underlyings[i];
                infos[count].vToken = allMarkets[i];
                infos[count].underlyingSymbol = ILensERC20(underlyings[i]).symbol();
                infos[count].vTokenSymbol = ILensVToken(allMarkets[i]).symbol();
                infos[count].underlyingPrice = oracle.getUnderlyingPrice(allMarkets[i]);
                infos[count].exchangeRate = ILensVToken(allMarkets[i]).exchangeRateStored();
                count++;
            }
        }
    }

    function getSymbolsInfo(address pool_, ISymbolsLens.PriceAndVolatility[] memory pvs)
    public view returns (ISymbolsLens.SymbolInfo[] memory infos) {
        return symbolsLens.getSymbolsInfo(pool_, pvs);
    }

    function getLpInfo(address pool_, address account_) public view returns (LpInfo memory info) {
        ILensPool pool = ILensPool(pool_);
        info.account = account_;
        info.lTokenId = ILensDToken(pool.lToken()).getTokenIdOf(account_);
        if (info.lTokenId != 0) {
            ILensPool.PoolLpInfo memory tmp = pool.lpInfos(info.lTokenId);
            info.vault = tmp.vault;
            info.amountB0 = tmp.amountB0;
            info.liquidity = tmp.liquidity;
            info.cumulativePnlPerLiquidity = tmp.cumulativePnlPerLiquidity;
            info.vaultLiquidity = ILensVault(info.vault).getVaultLiquidity();

            address[] memory markets = ILensVault(info.vault).getMarketsIn();
            info.markets = new MarketInfo[](markets.length);
            for (uint256 i = 0; i < markets.length; i++) {
                address vToken = markets[i];
                info.markets[i].vToken = vToken;
                info.markets[i].vTokenSymbol = ILensVToken(vToken).symbol();
                info.markets[i].underlying = vToken != pool.vTokenETH() ? ILensVToken(vToken).underlying() : pool.tokenWETH();
                info.markets[i].underlyingSymbol = ILensERC20(info.markets[i].underlying).symbol();
                info.markets[i].underlyingPrice = ILensOracle(ILensComptroller(ILensVault(pool.vaultImplementation()).comptroller()).oracle()).getUnderlyingPrice(vToken);
                info.markets[i].exchangeRate = ILensVToken(vToken).exchangeRateStored();
                info.markets[i].vTokenBalance = ILensVToken(vToken).balanceOf(info.vault);
            }
        }
    }

    function getTdInfo(address pool_, address account_) public view returns (TdInfo memory info) {
        ILensPool pool = ILensPool(pool_);
        info.account = account_;
        info.pTokenId = ILensDToken(pool.pToken()).getTokenIdOf(account_);
        if (info.pTokenId != 0) {
            ILensPool.PoolTdInfo memory tmp = pool.tdInfos(info.pTokenId);
            info.vault = tmp.vault;
            info.amountB0 = tmp.amountB0;
            info.vaultLiquidity = ILensVault(info.vault).getVaultLiquidity();

            address[] memory markets = ILensVault(info.vault).getMarketsIn();
            info.markets = new MarketInfo[](markets.length);
            for (uint256 i = 0; i < markets.length; i++) {
                address vToken = markets[i];
                info.markets[i].vToken = vToken;
                info.markets[i].vTokenSymbol = ILensVToken(vToken).symbol();
                info.markets[i].underlying = vToken != pool.vTokenETH() ? ILensVToken(vToken).underlying() : pool.tokenWETH();
                info.markets[i].underlyingSymbol = ILensERC20(info.markets[i].underlying).symbol();
                info.markets[i].underlyingPrice = ILensOracle(ILensComptroller(ILensVault(pool.vaultImplementation()).comptroller()).oracle()).getUnderlyingPrice(vToken);
                info.markets[i].exchangeRate = ILensVToken(vToken).exchangeRateStored();
                info.markets[i].vTokenBalance = ILensVToken(vToken).balanceOf(info.vault);
            }

            address[] memory symbols = ILensSymbolManager(pool.symbolManager()).getActiveSymbols(info.pTokenId);
            info.positions = new PositionInfo[](symbols.length);
            for (uint256 i = 0; i < symbols.length; i++) {
                ILensSymbol symbol = ILensSymbol(symbols[i]);
                info.positions[i].symbolAddress = symbols[i];
                info.positions[i].symbol = symbol.symbol();

                ILensSymbol.Position memory p = symbol.positions(info.pTokenId);
                info.positions[i].volume = p.volume;
                info.positions[i].cost = p.cost;
                info.positions[i].cumulativeFundingPerVolume = p.cumulativeFundingPerVolume;
            }
        }
    }

}


