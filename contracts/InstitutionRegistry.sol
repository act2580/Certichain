// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title InstitutionRegistry
 * @author CertiChain Team
 * @notice Sisteme kayıtlı ve yetkili eğitim kurumlarını yönetir.
 *         Sadece kayıtlı kurumlar sertifika hash'i blokzincire yazabilir.
 */
contract InstitutionRegistry is Ownable {

    // ─── Veri Yapıları ─────────────────────────────────────────────────────

    struct Institution {
        string  name;       // Kurum adı (ör: "Atatürk Üniversitesi")
        string  country;    // Ülke kodu (ör: "TR")
        bool    isActive;   // Aktif mi?
        uint256 addedAt;    // Eklenme zamanı (Unix timestamp)
    }

    // ─── State Değişkenleri ────────────────────────────────────────────────

    mapping(address => Institution) private _institutions;
    address[] private _institutionList;

    // ─── Olaylar (Events) ──────────────────────────────────────────────────

    event InstitutionAdded(
        address indexed institutionAddress,
        string name,
        string country,
        uint256 timestamp
    );

    event InstitutionDeactivated(
        address indexed institutionAddress,
        uint256 timestamp
    );

    event InstitutionReactivated(
        address indexed institutionAddress,
        uint256 timestamp
    );

    // ─── Modifier'lar ──────────────────────────────────────────────────────

    modifier onlyActiveInstitution() {
        require(
            _institutions[msg.sender].isActive,
            "InstitutionRegistry: Yetkisiz veya pasif kurum"
        );
        _;
    }

    // ─── Constructor ───────────────────────────────────────────────────────

    constructor() Ownable(msg.sender) {}

    // ─── Yönetim Fonksiyonları (sadece owner) ──────────────────────────────

    /**
     * @notice Sisteme yeni bir eğitim kurumu ekler.
     * @param institutionAddress Kurumun cüzdan adresi
     * @param name               Kurum adı
     * @param country            Ülke kodu (ISO 3166-1 alpha-2)
     */
    function addInstitution(
        address institutionAddress,
        string calldata name,
        string calldata country
    ) external onlyOwner {
        require(institutionAddress != address(0), "InstitutionRegistry: Gecersiz adres");
        require(bytes(name).length > 0,           "InstitutionRegistry: Kurum adi bos olamaz");
        require(
            !_institutions[institutionAddress].isActive,
            "InstitutionRegistry: Kurum zaten aktif"
        );

        // Daha önce hiç eklenmemişse listeye ekle
        if (bytes(_institutions[institutionAddress].name).length == 0) {
            _institutionList.push(institutionAddress);
        }

        _institutions[institutionAddress] = Institution({
            name:      name,
            country:   country,
            isActive:  true,
            addedAt:   block.timestamp
        });

        emit InstitutionAdded(institutionAddress, name, country, block.timestamp);
    }

    /**
     * @notice Bir kurumu pasife alır (sertifika yazamaz, eskiler geçerli kalır).
     */
    function deactivateInstitution(address institutionAddress) external onlyOwner {
        require(
            _institutions[institutionAddress].isActive,
            "InstitutionRegistry: Kurum zaten pasif"
        );
        _institutions[institutionAddress].isActive = false;
        emit InstitutionDeactivated(institutionAddress, block.timestamp);
    }

    /**
     * @notice Pasif bir kurumu tekrar aktif hale getirir.
     */
    function reactivateInstitution(address institutionAddress) external onlyOwner {
        require(
            !_institutions[institutionAddress].isActive,
            "InstitutionRegistry: Kurum zaten aktif"
        );
        require(
            bytes(_institutions[institutionAddress].name).length > 0,
            "InstitutionRegistry: Kurum kayitli degil"
        );
        _institutions[institutionAddress].isActive = true;
        emit InstitutionReactivated(institutionAddress, block.timestamp);
    }

    // ─── Okuma Fonksiyonları ───────────────────────────────────────────────

    /**
     * @notice Bir adresin aktif kurum olup olmadığını döner.
     */
    function isActiveInstitution(address institutionAddress) external view returns (bool) {
        return _institutions[institutionAddress].isActive;
    }

    /**
     * @notice Kurum bilgilerini döner.
     */
    function getInstitution(address institutionAddress)
        external
        view
        returns (
            string memory name,
            string memory country,
            bool isActive,
            uint256 addedAt
        )
    {
        Institution storage inst = _institutions[institutionAddress];
        return (inst.name, inst.country, inst.isActive, inst.addedAt);
    }

    /**
     * @notice Kayıtlı tüm kurum adreslerini döner.
     */
    function getAllInstitutions() external view returns (address[] memory) {
        return _institutionList;
    }

    /**
     * @notice Toplam kayıtlı kurum sayısını döner.
     */
    function institutionCount() external view returns (uint256) {
        return _institutionList.length;
    }
}
