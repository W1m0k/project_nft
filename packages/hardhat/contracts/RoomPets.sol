// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract OwnableDelegateProxy {}

contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}

contract RoomPets is ERC721Enumerable, Ownable {
    using SafeMath for uint256;

    uint256 public constant ETH_PRICE = 0.02 ether;
    uint256 public constant MAX_SUPPLY = 1000;

    address proxyRegistryAddress;

    mapping(uint256 => bool) private tokenIdRedemptions;

    string[] private ipfsHash = [
        "QmSMEAsv8QjFRN36fEUqV5a6NpCLXgfCP6BcCxBj8r58ay", //BalloonCat
        "Qmd1kCaZ7YgwR5yRGmBm3UzD3RgVdz7N695F1tjms22QKH", //FisherCat
        "QmaWfgasrYg9ZJufAH3bdD4KoATMCoMNmkRx9ibs8MDB2X", //MerchantCat
        "QmX53tTCbsQQhXoFMcqhatfL4jNLQ96UZHVwpW1rxYPJKo", //SleepCat
        "QmUVUJ1G3jXqiXnEJmZvJN2hUqZqQAPv29NQLqTAcptTa8", //AirShipCat
        "QmcvJ8iStjucFDy4wdS8DCTP9LvyB3EZoyeSANSB29G9oN", //BoatCat
        "QmPCKuiCWx9m3T9cPj8Jxy9nXwdNmVcVabK8GyDeckjL7i", //SmileCat
        "QmQdQsvxKo1tzh4o9dTro1Uct9gRH2ASMneqnZZ4XNcpDh", //LunchCat
        //c1
        //c2
        //c3
        //c4
        "QmcZw78BmsdzF2xe7P3DjtmgjiV2u7h7awZ6bBaPaKpDEP", //FullSetA
        "QmRXmW6rpaeajtYDwgX17D2cwn1Qgo3urje9p76mYvbnAW" //FullSetB
        //c
    ];

    //Change string to byteX if possible

    constructor(address _proxyRegistryAddress) ERC721("Room Cats", "RMCT") {
        proxyRegistryAddress = _proxyRegistryAddress;
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

    ///////
    // MAIN FUNCTIONS
    //////

    function buy(uint256 _tokenId) public payable {
        require(msg.value == ETH_PRICE, "wrong price");
        require(totalSupply() < MAX_SUPPLY, "exceeds maximum supply");
        require(_tokenId < 10000, "token id invalid");
        require(
            tokenIdRedemptions[_tokenId] == false,
            "token already redeemed"
        );
        _safeMint(_msgSender(), _tokenId);
        tokenIdRedemptions[_tokenId] = true;
    }

    function combine(uint256[4] memory _tokenIds) public {
        uint256 count_check;
        uint256[8] memory arr_idx;

        for (uint256 i = 0; i < 4; i++) {
            require(ownerOf(_tokenIds[i]) == _msgSender(), "not owner");
            uint256 rand = uint256(keccak256(abi.encodePacked(_tokenIds[i])));
            uint256 idx = rand % 8; //12
            if (idx < 4 && count_check == i) {
                count_check++;
            } else if (idx < 8 && count_check == (i * 2)) {
                count_check += 2;
            } else if (count_check == (i * 3)) {
                count_check += 3;
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
        } /* else if (
            count_check == 12 &&
            (arr_idx[8] + arr_idx[9] + arr_idx[10] + arr_idx[11]) == 4
        ) {
            _safeMint(_msgSender(), 30000 + _tokenIds[0]);
        } */
    }

    /////
    // HELPER FUNCTIONS
    /////

    function withdraw() public {
        uint256 each = address(this).balance / 2;
        require(
            payable(address(0xbF44E332E73c299ed6f1FC0113Fb5A742C90bC0f)).send(
                each
            )
        );
        require(
            payable(address(0xF7e3896054E3876E24bf6b178A6C251B68eCdc47)).send(
                each
            )
        );
    }

    function getHash(uint256 _tokenId) internal view returns (string memory) {
        string memory output;
        if (_tokenId < 10000) {
            uint256 rand = uint256(keccak256(abi.encodePacked(_tokenId)));
            output = ipfsHash[rand % 8]; //12
        } else if (_tokenId >= 30000) {
            //output = ipfsHash[9]; //15
        } else if (_tokenId >= 20000) {
            output = ipfsHash[9]; //14
        } else if (_tokenId >= 10000) {
            output = ipfsHash[8]; //13
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
}
