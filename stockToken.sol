// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
// Llibreries estandard ERC-20
//import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.5/contracts/token/ERC20/ERC20.sol";
//import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.5/contracts/token/ERC20/IERC20.sol";

import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.5/contracts/token/ERC20/extensions/ERC20Snapshot.sol";

//access control 
//import "@openzeppelin/contracts/access/AccessControl.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.5/contracts/access/AccessControl.sol";

contract stockToken is ERC20Snapshot, AccessControl{

    //definició rol admin
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Constructor inicial
    constructor() ERC20("Mock Stock token", "TOKENSIMU") {

        //definició rol admin a qui ha desplegat el contracte
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    //mint tokens. Es multiplica per 10*18 per a definir decimals de la mateixa manera que Ether i altres.
    function mintTokens(uint256 tokens) external onlyRole(ADMIN_ROLE){
            _mint(msg.sender, tokens);
    }

    //l'admin pot assignar rols d'admin
    function grantRoles(address broker) external onlyRole(ADMIN_ROLE){
        _grantRole(ADMIN_ROLE, broker);
    }

    //Snapshot per a guardar el balanç dels inversors
    function snapshot() external onlyRole(ADMIN_ROLE) returns (uint256){
    return _snapshot();
    }

    //obté el balanç d'un inversor quan es va crear una snapshot determinada
    function getBalanceOfAt(address addr, uint256 snapshotId) view external onlyRole(ADMIN_ROLE) returns (uint256){
        return balanceOfAt(addr, snapshotId);
    }



}


