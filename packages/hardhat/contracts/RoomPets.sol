// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Initializable {
    bool inited = false;

    modifier initializer() {
        require(!inited, "already inited");
        _;
        inited = true;
    }
}

contract EIP712Base is Initializable {
    struct EIP712Domain {
        string name;
        string version;
        address verifyingContract;
        bytes32 salt;
    }

    string public constant ERC712_VERSION = "1";

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256(
            bytes(
                "EIP712Domain(string name,string version,address verifyingContract,bytes32 salt)"
            )
        );
    bytes32 internal domainSeperator;

    // supposed to be called once while initializing.
    // one of the contracts that inherits this contract follows proxy pattern
    // so it is not possible to do this in a constructor
    function _initializeEIP712(string memory name) internal initializer {
        _setDomainSeperator(name);
    }

    function _setDomainSeperator(string memory name) internal {
        domainSeperator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes(ERC712_VERSION)),
                address(this),
                bytes32(getChainId())
            )
        );
    }

    function getDomainSeperator() public view returns (bytes32) {
        return domainSeperator;
    }

    function getChainId() public view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    /**
     * Accept message hash and returns hash message in EIP712 compatible form
     * So that it can be used to recover signer from signature signed using EIP712 formatted data
     * https://eips.ethereum.org/EIPS/eip-712
     * "\\x19" makes the encoding deterministic
     * "\\x01" is the version byte to make it compatible to EIP-191
     */
    function toTypedMessageHash(bytes32 messageHash)
        internal
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked("\x19\x01", getDomainSeperator(), messageHash)
            );
    }
}

abstract contract ContextMixin {
    function msgSender() internal view returns (address payable sender) {
        if (msg.sender == address(this)) {
            bytes memory array = msg.data;
            uint256 index = msg.data.length;
            assembly {
                // Load the 32 bytes word from memory with the address on the lower 20 bytes, and mask those.
                sender := and(
                    mload(add(array, index)),
                    0xffffffffffffffffffffffffffffffffffffffff
                )
            }
        } else {
            sender = payable(msg.sender);
        }
        return sender;
    }
}

contract NativeMetaTransaction is EIP712Base {
    using SafeMath for uint256;
    bytes32 private constant META_TRANSACTION_TYPEHASH =
        keccak256(
            bytes(
                "MetaTransaction(uint256 nonce,address from,bytes functionSignature)"
            )
        );
    event MetaTransactionExecuted(
        address userAddress,
        address payable relayerAddress,
        bytes functionSignature
    );
    mapping(address => uint256) nonces;

    /*
     * Meta transaction structure.
     * No point of including value field here as if user is doing value transfer then he has the funds to pay for gas
     * He should call the desired function directly in that case.
     */
    struct MetaTransaction {
        uint256 nonce;
        address from;
        bytes functionSignature;
    }

    function executeMetaTransaction(
        address userAddress,
        bytes memory functionSignature,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV
    ) public payable returns (bytes memory) {
        MetaTransaction memory metaTx = MetaTransaction({
            nonce: nonces[userAddress],
            from: userAddress,
            functionSignature: functionSignature
        });

        require(
            verify(userAddress, metaTx, sigR, sigS, sigV),
            "Signer and signature do not match"
        );

        // increase nonce for user (to avoid re-use)
        nonces[userAddress] = nonces[userAddress].add(1);

        emit MetaTransactionExecuted(
            userAddress,
            payable(msg.sender),
            functionSignature
        );

        // Append userAddress and relayer address at the end to extract it from calling context
        (bool success, bytes memory returnData) = address(this).call(
            abi.encodePacked(functionSignature, userAddress)
        );
        require(success, "Function call not successful");

        return returnData;
    }

    function hashMetaTransaction(MetaTransaction memory metaTx)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(
                    META_TRANSACTION_TYPEHASH,
                    metaTx.nonce,
                    metaTx.from,
                    keccak256(metaTx.functionSignature)
                )
            );
    }

    function getNonce(address user) public view returns (uint256 nonce) {
        nonce = nonces[user];
    }

    function verify(
        address signer,
        MetaTransaction memory metaTx,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV
    ) internal view returns (bool) {
        require(signer != address(0), "NativeMetaTransaction: INVALID_SIGNER");
        return
            signer ==
            ecrecover(
                toTypedMessageHash(hashMetaTransaction(metaTx)),
                sigV,
                sigR,
                sigS
            );
    }
}

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

contract OwnableDelegateProxy {}

contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}

/**
 * @title ERC721Tradable
 * ERC721Tradable - ERC721 contract that whitelists a trading address, and has minting functionality.
 */
abstract contract ERC721Tradable is
    ContextMixin,
    ERC721Enumerable,
    NativeMetaTransaction,
    Ownable
{
    using SafeMath for uint256;

    address proxyRegistryAddress;
    uint256 private _currentTokenId = 0;

    constructor(
        string memory _name,
        string memory _symbol,
        address _proxyRegistryAddress
    ) ERC721(_name, _symbol) {
        proxyRegistryAddress = _proxyRegistryAddress;
        _initializeEIP712(_name);
    }

    /**
     * @dev calculates the next token ID based on value of _currentTokenId
     * @return uint256 for the next token ID
     */
    function _getNextTokenId() internal view returns (uint256) {
        return _currentTokenId.add(1);
    }

    /**
     * @dev increments the value of _currentTokenId
     */
    function _incrementTokenId() internal {
        _currentTokenId++;
    }

    /**
     * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-less listings.
     */
    function isApprovedForAll(address owner, address operator)
        public
        view
        override
        returns (bool)
    {
        // Whitelist OpenSea proxy contract for easy trading.
        ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
        if (address(proxyRegistry.proxies(owner)) == operator) {
            return true;
        }

        return super.isApprovedForAll(owner, operator);
    }

    /**
     * This is used instead of msg.sender as transactions won't be sent by the original token owner, but by OpenSea.
     */
    function _msgSender() internal view override returns (address sender) {
        return ContextMixin.msgSender();
    }
}

//contract RoomPets is ERC721Tradable, ReentrancyGuard {
contract RoomPets is ERC721Enumerable, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 public constant ETH_PRICE = 0.02 ether;
    uint256 public constant MAX_SUPPLY = 1000;

    address payable private teme_vault1;
    address payable private teme_vault2;

    string[] private ipfs_hash = [
        "QmSMEAsv8QjFRN36fEUqV5a6NpCLXgfCP6BcCxBj8r58ay", //BalloonCat
        "Qmd1kCaZ7YgwR5yRGmBm3UzD3RgVdz7N695F1tjms22QKH", //FisherCat
        "QmaWfgasrYg9ZJufAH3bdD4KoATMCoMNmkRx9ibs8MDB2X", //MerchantCat
        "QmX53tTCbsQQhXoFMcqhatfL4jNLQ96UZHVwpW1rxYPJKo", //SleepCat
        "QmUVUJ1G3jXqiXnEJmZvJN2hUqZqQAPv29NQLqTAcptTa8", //AirShipCat
        "QmcvJ8iStjucFDy4wdS8DCTP9LvyB3EZoyeSANSB29G9oN", //BoatCat
        "QmPCKuiCWx9m3T9cPj8Jxy9nXwdNmVcVabK8GyDeckjL7i", //SmileCat
        "QmQdQsvxKo1tzh4o9dTro1Uct9gRH2ASMneqnZZ4XNcpDh", //LunchCat
        "QmcZw78BmsdzF2xe7P3DjtmgjiV2u7h7awZ6bBaPaKpDEP", //FullSetA
        "QmRXmW6rpaeajtYDwgX17D2cwn1Qgo3urje9p76mYvbnAW" //FullSetB
    ];

    //Change string to byteX if possible
    /*  constructor(address _proxyRegistryAddress)
        ERC721Tradable("Room Cats", "RMCT", _proxyRegistryAddress)
    {
        teme_vault1 = payable(
            address(0xbF44E332E73c299ed6f1FC0113Fb5A742C90bC0f)
        );
        teme_vault2 = payable(
            address(0xF7e3896054E3876E24bf6b178A6C251B68eCdc47)
        );
    } */

    constructor() ERC721("Room Cats", "RMCT") {
        teme_vault1 = payable(
            address(0xbF44E332E73c299ed6f1FC0113Fb5A742C90bC0f)
        );
        teme_vault2 = payable(
            address(0xF7e3896054E3876E24bf6b178A6C251B68eCdc47)
        );
    }

    ///////
    // MAIN FUNCTIONS
    //////

    function buy(uint256 _tokenId) public payable nonReentrant {
        require(msg.value == ETH_PRICE, "wrong price");
        require(totalSupply() < MAX_SUPPLY, "exceeds maximum supply");
        require(_tokenId < 10000, "token id invalid");
        _safeMint(_msgSender(), _tokenId);
    }

    function combine(uint256[4] memory _tokenIds) public {
        uint256 count_check;
        uint256[8] memory arr_idx;

        for (uint256 i = 0; i < 4; i++) {
            require(ownerOf(_tokenIds[i]) == _msgSender(), "not owner");
            uint256 rand = uint256(
                keccak256(abi.encodePacked(toString(_tokenIds[i])))
            );
            uint256 idx = rand % 8;
            if (idx < 4 && count_check == i) {
                count_check++;
            } else if (
                /*idx < 8 && */
                count_check == (i * 2)
            ) {
                count_check += 2;
            }
            arr_idx[idx] = 1;

            _burn(_tokenIds[i]);
        }

        if (
            count_check == 4 &&
            (arr_idx[0] + arr_idx[1] + arr_idx[2] + arr_idx[3]) == 4
        ) {
            _safeMint(_msgSender(), 10000 + _tokenIds[0]);
        } else if (
            count_check == 8 &&
            (arr_idx[4] + arr_idx[5] + arr_idx[6] + arr_idx[7]) == 4
        ) {
            _safeMint(_msgSender(), 20000 + _tokenIds[0]);
        }
    }

    /////
    // HELPER FUNCTIONS
    /////

    function withdraw() public {
        uint256 _each = address(this).balance / 2;
        require(payable(teme_vault1).send(_each));
        require(payable(teme_vault2).send(_each));
    }

    function getHash(uint256 _tokenId) internal view returns (string memory) {
        string memory output;
        if (_tokenId <= 10000) {
            uint256 rand = uint256(
                keccak256(abi.encodePacked(toString(_tokenId)))
            );
            output = ipfs_hash[rand % 8];
        }
        //> 30000
        //{}
        else if (_tokenId > 20000) {
            // 20001 - 30000
            output = ipfs_hash[9];
        } else if (_tokenId > 10000) {
            //10001 - 20000
            output = ipfs_hash[8];
        }

        return output;
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        string memory output = string(
            abi.encodePacked("https://ipfs.io/ipfs/", getHash(_tokenId))
        );
        return output;
    }

    function toString(uint256 _value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT license
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (_value == 0) {
            return "0";
        }
        uint256 temp = _value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(_value % 10)));
            _value /= 10;
        }
        return string(buffer);
    }
}
