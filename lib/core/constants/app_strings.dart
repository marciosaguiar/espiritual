class AppStrings {
  // App
  static const String appName = 'LevitaSync';
  static const String appTagline = 'Ministério de Louvor Unificado';

  // Auth
  static const String login = 'Entrar';
  static const String register = 'Criar Conta';
  static const String logout = 'Sair';
  static const String name = 'Nome';
  static const String password = 'Senha';
  static const String confirmPassword = 'Confirmar Senha';
  static const String namePlaceholder = 'Seu nome no ministério';
  static const String passwordPlaceholder = 'Mínimo 6 caracteres';
  static const String dontHaveAccount = 'Não tem conta? ';
  static const String alreadyHaveAccount = 'Já tem conta? ';
  static const String createAccount = 'Criar conta';
  static const String loginHere = 'Entre aqui';

  // Navigation
  static const String home = 'Início';
  static const String songs = 'Músicas';
  static const String scale = 'Escala';
  static const String chat = 'Chat';
  static const String profile = 'Perfil';

  // Home
  static const String verseOfTheDay = 'Versículo do Dia';
  static const String nextService = 'Próximo Culto';
  static const String quickActions = 'Acesso Rápido';
  static const String searchSong = 'Buscar Música';
  static const String viewScale = 'Ver Escala';
  static const String suggestRepertoire = 'Sugerir Repertório';
  static const String noNextService = 'Nenhum culto agendado';

  // Songs
  static const String allSongs = 'Todas';
  static const String favorites = 'Favoritas';
  static const String offline = 'Offline';
  static const String searchSongs = 'Buscar músicas...';
  static const String addSong = 'Adicionar Música';
  static const String noSongsFound = 'Nenhuma música encontrada';
  static const String lyrics = 'Letra';
  static const String chords = 'Cifra';
  static const String originalKey = 'Tom original';
  static const String transpose = 'Transpor';
  static const String saveKey = 'Salvar tom';
  static const String saveOffline = 'Salvar offline';
  static const String openYoutube = 'Abrir no YouTube';
  static const String worshipMode = 'Modo Culto';
  static const String showChords = 'Mostrar Cifra';
  static const String hideChords = 'Ocultar Cifra';

  // Scale
  static const String addService = 'Novo Culto';
  static const String serviceDetails = 'Detalhes do Culto';
  static const String addMusics = 'Adicionar Músicas';
  static const String addLevitas = 'Definir Levitas';
  static const String observations = 'Observações';
  static const String confirmPresence = 'Confirmar Presença';
  static const String confirmed = 'Confirmado';
  static const String notConfirmed = 'Não confirmado';
  static const String noServices = 'Nenhum culto neste dia';

  // Chat
  static const String groupChat = 'Chat do Ministério';
  static const String typeMessage = 'Digite uma mensagem...';
  static const String searchSongInChat = 'Buscar música';
  static const String insertSongInScale = 'Inserir na escala';
  static const String noMessages = 'Nenhuma mensagem ainda. Diga olá!';

  // Profile
  static const String myProfile = 'Meu Perfil';
  static const String editProfile = 'Editar Perfil';
  static const String function = 'Função';
  static const String instrument = 'Instrumento';
  static const String savedTones = 'Tons Salvos';
  static const String myFavorites = 'Minhas Favoritas';
  static const String servicesCount = 'Cultos';
  static const String songsCount = 'Músicas';

  // Instruments
  static const String vocalist = 'Cantor(a)';
  static const String guitar = 'Violão/Guitarra';
  static const String bass = 'Baixo';
  static const String drums = 'Bateria';
  static const String keyboard = 'Teclado';
  static const String other = 'Outro';

  // Roles
  static const String admin = 'Líder';
  static const String levita = 'Levita';

  // Days
  static const String wednesday = 'Quarta-feira';
  static const String friday = 'Sexta-feira';
  static const String sunday = 'Domingo';

  // Errors
  static const String errorNameRequired = 'Nome é obrigatório';
  static const String errorNameTooShort = 'Nome deve ter no mínimo 3 caracteres';
  static const String errorNameTaken = 'Este nome já está em uso';
  static const String errorPasswordRequired = 'Senha é obrigatória';
  static const String errorPasswordTooShort = 'Senha deve ter no mínimo 6 caracteres';
  static const String errorPasswordsNotMatch = 'Senhas não coincidem';
  static const String errorInvalidCredentials = 'Nome ou senha incorretos';
  static const String errorGeneric = 'Ocorreu um erro. Tente novamente.';
  static const String errorNoInternet = 'Sem conexão. Modo offline ativo.';

  // Success
  static const String successLogin = 'Bem-vindo ao LevitaSync!';
  static const String successRegister = 'Conta criada com sucesso!';
  static const String successSaved = 'Salvo com sucesso!';
  static const String successPresenceConfirmed = 'Presença confirmada!';

  // Tab indices — keep in sync with MainScreen's IndexedStack order
  static const int tabHome = 0;
  static const int tabSongs = 1;
  static const int tabScale = 2;
  static const int tabChat = 3;
  static const int tabProfile = 4;

  // Verses of the day (Portuguese)
  static const List<String> verses = [
    '"Cantai ao Senhor um cântico novo; cantai ao Senhor toda a terra." — Salmos 96:1',
    '"Louvai o Senhor, porque é bom o Senhor; cantai louvores ao seu nome, porque é agradável." — Salmos 135:3',
    '"Cantai ao Senhor com ações de graças; tocai louvores ao nosso Deus com harpa." — Salmos 147:7',
    '"Sede cheios do Espírito, falando entre vós com salmos, hinos e cânticos espirituais, cantando e louvando ao Senhor no coração." — Efésios 5:18-19',
    '"Louvai a Deus no seu santuário; louvai-o no firmamento do seu poder." — Salmos 150:1',
    '"Levantai as mãos para o santuário e louvai ao Senhor." — Salmos 134:2',
    '"Cantarei ao Senhor enquanto eu viver; cantarei louvores ao meu Deus enquanto eu existir." — Salmos 104:33',
    '"Bendize, ó minha alma, ao Senhor; e tudo o que há em mim, bendiga o seu santo nome." — Salmos 103:1',
    '"Porque grande é o Senhor e mui digno de louvor; temível é ele acima de todos os deuses." — Salmos 96:4',
    '"O Senhor é a minha força e o meu escudo; nele o meu coração confia, e eu fui socorrido." — Salmos 28:7',
    '"Alegrai-vos no Senhor sempre; outra vez digo, alegrai-vos." — Filipenses 4:4',
    '"Tudo o que tem fôlego louve ao Senhor! Aleluia!" — Salmos 150:6',
    '"O Senhor é a minha luz e a minha salvação; a quem temerei?" — Salmos 27:1',
    '"Porque ele é bom, porque a sua misericórdia dura para sempre." — 2 Crônicas 5:13',
    '"Gritem de alegria ao Senhor, toda a terra; irrompe em cânticos de júbilo e louvores." — Salmos 98:4',
  ];
}
