/// Fora da web não há Wake Lock de navegador. (O app roda como PWA nos dois
/// sistemas, então este caminho não é usado em produção.)
Future<String> manterTelaAcesa() async => 'sem-suporte';

void soltarTela() {}

bool telaEstaAcesa() => false;
