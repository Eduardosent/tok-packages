module mycoin::mycoin {
    use tok_issuer::with_otw::{Self};

    /// El Witness para el OTW
    public struct MYCOIN has drop {}

    fun init(witness: MYCOIN, ctx: &mut TxContext) {
        // 1. Disparar la creación y entrega de la bóveda
        // Esto es lo único que el contrato del token necesita hacer
        with_otw::create_token(
            witness,
            9,
            b"MYC".to_string(),
            b"MYCOIN".to_string(),
            b"Token Action Protocol".to_string(),
            b"https://arweave.net/icon".to_string(),
            ctx
        );
    }
}