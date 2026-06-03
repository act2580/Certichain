const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("CertiChainModule", (m) => {
  // 1. Önce InstitutionRegistry dağıtılır
  const institutionRegistry = m.contract("InstitutionRegistry");

  // 2. CertificateRegistry, parametre olarak InstitutionRegistry'nin adresini alır
  const certificateRegistry = m.contract("CertificateRegistry", [
    institutionRegistry,
  ]);

  // 3. SoulboundToken, parametre olarak InstitutionRegistry'nin adresini alır
  const soulboundToken = m.contract("SoulboundToken", [
    institutionRegistry,
  ]);

  // Sözleşmeleri ağda (doğrulamalar vb için) döndürüyoruz
  return { institutionRegistry, certificateRegistry, soulboundToken };
});
