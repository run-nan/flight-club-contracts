// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {GameFactory} from "../src/game-factory.sol";
import {Game} from "../src/game.sol";
import {FatToken} from "../src/fat-token.sol";
import {SoapToken} from "../src/soap-token.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

contract DeployFlightClub is Script {

    function run() public {
        vm.startBroadcast();
        //fatToken
        bytes memory initData = abi.encodeWithSelector(FatToken.initialize.selector);
        address fatTokenAddress = Upgrades.deployUUPSProxy("fat-token.sol:FatToken", initData);
        FatToken fatToken = FatToken(payable(fatTokenAddress));

        //soapToken
        initData = abi.encodeWithSelector(SoapToken.init.selector);
        address soapTokenAddress = Upgrades.deployUUPSProxy("soap-token.sol:SoapToken", initData);
        SoapToken soapToken = SoapToken(soapTokenAddress);

        //factory
        initData = abi.encodeWithSelector(GameFactory.initialize.selector, fatTokenAddress, soapTokenAddress);
        address factoryAddress = Upgrades.deployUUPSProxy("game-factory.sol:GameFactory", initData);
        GameFactory factory = GameFactory(factoryAddress);
        Game game = new Game();
        factory.setGameImplementation(address(game));

        //config
        soapToken.setMintManager(factoryAddress);
        fatToken.setDelegatorManager(factoryAddress);

        console.log("proxyFatTokenAddress", fatTokenAddress);
        console.log("proxySoapTokenAddress", soapTokenAddress);
        console.log("proxyFactoryAddress", factoryAddress);

        console.log("FatTokenAddress", Upgrades.getImplementationAddress(fatTokenAddress));
        console.log("SoapTokenAddress", Upgrades.getImplementationAddress(soapTokenAddress));
        console.log("FactoryAddress", Upgrades.getImplementationAddress(factoryAddress));
        console.log("gameAddress", address(game));

        vm.stopBroadcast();
    }
}
