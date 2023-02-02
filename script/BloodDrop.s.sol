// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IUBlood.sol";

contract BloodDrop is Script {
    // Deployments
    IUBlood public uBlood;

    uint256 mintAmount = 500000 ether;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAINNET");

        //Deploy Contracts
        uBlood = IUBlood(vm.envAddress("REACT_APP_BLOOD_MAINNET_ADDRESS"));  

        vm.startBroadcast(deployerPrivateKey);

        for(uint256 i; i< dropArray.length; i++){
            uBlood.mint(dropArray[i], mintAmount);
        }

        vm.stopBroadcast();
    }

    address[] dropArray = [0xF44620f0e43594408E8eA75ab779FC4C45626A17,0xB47567964c931ae906a61bB0E61Ef95106F3f8d7,0xf003D5E9F389473767FC5d29f8B1f57eec9544EB,0x05DC467b8173A6C4e8fB222Df4E6b3A80B9D1673,0x82F863d1e8a453E1E2E5621F4b12cAa45e3E3D25,0xfEc688B8d6AFb9De08FAA8890884D104209C17E1,0x384a221529D823fB430ff026fD03aEaB1e236773,0x82005cF2c06654139a62a461eddB9A3b17c6D6c2];

    
}
