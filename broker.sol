// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// Llibreries estandard ERC-20
//import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.5/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
//import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.5/contracts/token/ERC20/IERC20.sol";

import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.5/contracts/token/ERC20/extensions/ERC20Snapshot.sol";

//access control 
//import "@openzeppelin/contracts/access/AccessControl.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.5/contracts/access/AccessControl.sol";
//oracle pyth
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

interface ITokensimu {
    function snapshot() external returns (uint256);
    function getBalanceOfAt(address addr, uint256 snapshotId) view external returns (uint256);
    function mintTokens(uint256 tokens) external;

}

contract broker is AccessControl{
      
      IPyth pyth;

    //array de snapshots realitzats quan es depositen beneficis per a dividends
    uint256[] public dividendSnapshots;

    //Estructura dividends
    struct Dividend {
    uint256 totalAmount;     
    bool exists;
    }

    // snapshotId => Dividend info
    mapping(uint256 => Dividend) public dividends;

    // snapshotId => user => claimed?
    mapping(uint256 => mapping(address => bool)) public claimed;

    //EURC smart contract a Sepolia
    address public eurc = 0x08210F9170F89Ab7658F0B5E3fF39b0E03C594D4;

    //TOKENSIMU smart contract a Sepolia
    address public tokensimu = 0x777a732F33ebDA4cCddF40c18c856d3009158Dbb;
    //events
    event Purchase(address indexed buyer, address indexed stableToken, uint256 stableAmount, uint256 tokensBought, int256 price);
    event Sell(address indexed seller, address indexed token, uint256 EURCAmount, uint256 tokenAmount, int256 price);
    event DividendCreated(uint256 indexed snapshotId, uint256 totalAmount);
    event DividendClaimed(uint256 indexed snapshotId, address indexed user, uint256 amount);

    //definició rol admin
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Constructor inicial
    constructor()  {

        //definició rol admin
        _grantRole(ADMIN_ROLE, msg.sender);

        //0xDd24F84d36BF92C65F92307595335bdFab5Bbd21 contracte de Pyth a Sepolia
        pyth = IPyth(0xDd24F84d36BF92C65F92307595335bdFab5Bbd21);
    }

    //address del owner
    function retornaAddressOwner() view public returns (address owner) {
        
        return (address(this));
    }

    //tokens SIMU del owner
    function tokensOwner() view public returns (uint256 tokens){
        return IERC20(tokensimu).balanceOf(address(this));
    }

    //tokens EURC del owner
    function totalEURC() view public returns (uint256 tokens){
        return IERC20(eurc).balanceOf(address(this));
    }

    //tokens EURC del sender
    function totalEURCsender() view public returns (uint256 tokens){
        return IERC20(eurc).balanceOf(msg.sender);
    }

    function mintTOKENSIMU(uint256 tokens) public onlyRole(ADMIN_ROLE){
        ITokensimu(tokensimu).mintTokens(tokens);
    }

    //preu de l'acció obtingut amb l'oracle Pyth. Basat en el preu d'Amazon en dòlars
    //Retorna un preu que no està actualitzat. Cal primer actualitzar el preu a la blockchain (obtenirPreuDinamic())
    function obtenirPreu() view public returns (uint256 preu){
        
        // Llista de https://docs.pyth.network/price-feeds/core/price-feeds
        //La xifra obtinguda s'ha de dividir per 10**5 per a obtenir el preu real. 
        bytes32 priceFeedId = 0xb5d0e0fa58a1f8b81498ae670ce93c872d14434b72c364885d4fa1b257cbb07a; // AMZN/USD
        // Obté el preu de l'acció si s'ha actualitzat fa menys de 60 segons
        try pyth.getPriceNoOlderThan(priceFeedId, 60) returns (PythStructs.Price memory p){ 
            return uint256(uint64(p.price));
        }
        catch{
            PythStructs.Price memory p = pyth.getPriceUnsafe(priceFeedId); //Obté el preu més recent
            return uint256(uint64(p.price)); 
        }

        
  }

 // function obtenirPreuDinamic(bytes[] calldata updateData) public payable /*returns (uint256 p)*/ {
    // Submit a priceUpdate to the Pyth contract to update the on-chain price.
    // Updating the price requires paying the fee returned by getUpdateFee.
    // WARNING: These lines are required to ensure the getPriceNoOlderThan call below succeeds. If you remove them, transactions may fail with "0x19abf40e" error.
    //bytes[] memory priceUpdate = new bytes[](1);

  //  uint fee = pyth.getUpdateFee(updateData);
  //  pyth.updatePriceFeeds{ value: fee }(updateData);

    // Read the current price from a price feed if it is less than 60 seconds old.
    // Each price feed (e.g., ETH/USD) is identified by a price feed ID.
    // The complete list of feed IDs is available at https://docs.pyth.network/price-feeds/price-feeds
   /* bytes32 priceFeedId = 0xb5d0e0fa58a1f8b81498ae670ce93c872d14434b72c364885d4fa1b257cbb07a; // AMZN/USD
    PythStructs.Price memory price = pyth.getPriceNoOlderThan(priceFeedId, 60);
    return uint256(uint64(price.price));*/
 // }

  //Comprar TOKENSIMU amb la stablecoin EURC
  function buyWithEURC(uint256 stableAmount) external returns (uint256 tokensBought){
        
        //La inversió mínima és de 1 cèntim
        require(stableAmount >= 10000, "stableAmount must be >= 10000");

        // Rep el preu des de Pyth
        uint256 price = obtenirPreu();
        require(price > 0, "invalid price from oracle");

        // Transferim la stablecoin des de l'inversor al contracte
        bool ok = IERC20(eurc).transferFrom(msg.sender, address(this), stableAmount);
        require(ok, "stable transferFrom failed");

        //Quants tokens pot comprar amb els EURC que ha pagat (s'estableix el preu del token)
        tokensBought = (stableAmount*10**19)/price;

        // Assegurar-se que el contracte té suficients tokens per vendre
        uint256 contractBalance = IERC20(tokensimu).balanceOf(address(this));
        require(contractBalance >= tokensBought, "Not enough tokens in contract to sell");

        // Transferim els tokens a l'inversor
        IERC20(tokensimu).transfer(msg.sender, tokensBought);

        emit Purchase(msg.sender, eurc, stableAmount, tokensBought, int256(price));

        return tokensBought;
  }

  //Vendre TOKENSIMU per la stablecoin EURC
  function sellForEURC(uint256 tokenAmount) external returns (uint256 tokensSold){
        
        //La venta mínima és de 0.01 TOKENSIMU
        require(tokenAmount >= 10000000000000000, "You must sell at least 0.01 TOKENSIMU");

        // Rep el preu des de Pyth
        uint256 price = obtenirPreu();
        require(price > 0, "invalid price from oracle");

        // Transferim els TOKENSIMU des de l'inversor al contracte
        bool ok = IERC20(tokensimu).transferFrom(msg.sender, address(this), tokenAmount);
        require(ok, "TOKENSIMU transferFrom failed");

        //Quants EURC rep pels TOKENSIMU que ha venut
        uint256 EURCAmount = (tokenAmount*price)/10**19;

        // Assegurar-se que el contracte té suficients tokens per vendre
        uint256 contractBalance = IERC20(eurc).balanceOf(address(this));
        require(contractBalance >= EURCAmount, "Not enough EURC in contract");

        // Transferim els tokens a l'inversor
        IERC20(eurc).transfer(msg.sender, EURCAmount);

        emit Sell(msg.sender, eurc, EURCAmount, tokenAmount, int256(price));

        return tokenAmount;
  }

  //L'empresa deposita els beneficis per als dividends. 
  function depositBenefits(uint256 eurcBenefits) external returns (uint256 snapshotId){

    //Transferencia de EURC de la wallet de l' "empresa" al contracte
    IERC20(eurc).transferFrom(msg.sender, address(this), eurcBenefits);

    //Es realitza una snapshot per a saber els inversors que tenen TOKENSIMU en el moment actual i que els corresponen dividends
    snapshotId = ITokensimu(tokensimu).snapshot();

    //Es guarda la informació del dividend 
    dividends[snapshotId] = Dividend({
        totalAmount: eurcBenefits,
        exists: true
    });

    //Es guarda el ID de la snapshot per a que els inversors puguin saber-lo si han de reclamar dividends
    dividendSnapshots.push(snapshotId);
    emit DividendCreated(snapshotId, eurcBenefits);
  }

  //Els inversors poden reclamar dividends indicant el ID de la snapshot
  function claimDividends(uint256 snapshotId) external {

    //Es comprova que la snapshot té un dividend i no està reclamat per part de l'inversor msg.sender
    require(dividends[snapshotId].exists, "Snapshot not a dividend");
    require(!claimed[snapshotId][msg.sender], "Already claimed");

    //Es comprova la quantitat de TOKENSIMU de l'inversor msg.sender en el moment en què es fa la snapshot
    uint256 userBalance = ITokensimu(tokensimu).getBalanceOfAt(msg.sender, snapshotId);
    require(userBalance > 0, "No balance at snapshot");

    //Es calcula el pagament del dividend tenint en compte la part dels beneficis que li corresponen
    uint256 payment = (userBalance * dividends[snapshotId].totalAmount) / IERC20(tokensimu).totalSupply();

    //Es realitza el pagament del dividend
    require(IERC20(eurc).transfer(msg.sender, payment), "Transfer failed");
    emit DividendClaimed(snapshotId, msg.sender, payment);

    //S'indica que el dividend ha sigut reclamat 
    claimed[snapshotId][msg.sender] = true;
  }


}


