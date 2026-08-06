# LevitaSync 🎵

**O super app completo para ministérios de louvor**

LevitaSync centraliza tudo que um ministério de louvor precisa: músicas com cifras, escalas de culto, comunicação entre levitas e organização completa — em um único app moderno e intuitivo.

---

## 📱 Funcionalidades

### 🔐 Autenticação
- Login/cadastro por nome + senha (sem dependências de terceiros)
- Senha hasheada com SHA-256
- Sessão persistente (não precisa logar sempre)
- Perfis: **Admin (Líder)** e **Levita**

### 🏠 Início
- Versículo do dia (15 versículos gospel em rodízio)
- Próximo culto com músicas e levitas escalados
- Botões de ação rápida
- Sugestão de repertório com IA

### 🎶 Músicas
- Busca inteligente por nome/artista
- Filtros: Todas / Favoritas / Offline
- Visualização de letra e cifra
- **Transposição de tom** (+/−, com salvar tom preferido)
- Modo Culto (tela limpa, letra grande, fundo escuro)
- Salvar offline para uso sem internet
- Integração com YouTube

### 📅 Escala
- Calendário com destaque automático (Quarta, Sexta, Domingo)
- Criar cultos por dia
- Adicionar músicas e definir levitas
- **Confirmação de presença**
- Campo de observações

### 💬 Chat
- Chat em grupo em tempo real (Firestore)
- Buscar música dentro do chat
- Inserir música direto na escala
- Histórico de mensagens

### 👤 Perfil
- Instrumento e função
- Tom preferido salvo por música
- Lista de favoritas
- Toggle tema claro/escuro
- Logout seguro

---

## 🚀 Configuração

### Pré-requisitos
- Flutter 3.x (SDK)
- Conta Firebase (gratuita)
- Android Studio ou VS Code

### 1. Clonar e instalar dependências

```bash
git clone <repo>
cd levitasync
flutter pub get
```

### 2. Configurar Firebase

1. Acesse [Firebase Console](https://console.firebase.google.com/)
2. Crie um projeto chamado **levitasync**
3. Adicione os apps **Android** e **iOS**:
   - Package Android: `com.levitasync.app`
   - Bundle iOS: `com.levitasync.app`
4. Baixe os arquivos de configuração:
   - `google-services.json` → coloque em `android/app/`
   - `GoogleService-Info.plist` → coloque em `ios/Runner/`
5. Atualize `lib/firebase_options.dart` com seus dados do Firebase

> **Alternativa rápida:** Use o FlutterFire CLI:
> ```bash
> dart pub global activate flutterfire_cli
> flutterfire configure --project=levitasync
> ```

### 3. Configurar Firestore

No Firebase Console, crie as coleções:
- `users` — usuários
- `songs` — músicas
- `scales` — escalas
- `messages` — mensagens do chat
- `typing` — indicador "está digitando…"

**Regras de segurança:** use o arquivo [`firestore.rules`](firestore.rules) deste
repositório — Firebase Console → Firestore Database → Regras → colar → Publicar.

> ⚠️ **Leia antes de publicar o app.** A conferência de senha acontece hoje no
> próprio celular, então o banco não sabe quem está fazendo cada pedido e a
> coleção `users` precisa continuar legível. As regras do arquivo cortam o que
> é possível nesse cenário (exclusão de contas, documentos gigantes, coleções
> desconhecidas), mas **não substituem autenticação de verdade**.
>
> Enquanto o login não for verificado no servidor (Firebase Authentication),
> trate os dados como semipúblicos e **não** cadastre informação sensível.
> Nunca use `allow read, write: if true`: isso permite que qualquer pessoa leia
> e apague tudo, inclusive a lista de usuários.

### 4. Adicionar fontes Poppins

Baixe a família de fontes Poppins do Google Fonts e coloque os arquivos .ttf em `assets/fonts/`:
- `Poppins-Regular.ttf`
- `Poppins-Medium.ttf`
- `Poppins-SemiBold.ttf`
- `Poppins-Bold.ttf`

> Ou use o pacote `google_fonts` e remova a configuração de fontes do `pubspec.yaml`.

### 5. Rodar o app

```bash
# Android
flutter run

# iOS
flutter run -d ios

# Build APK
flutter build apk --release

# Build iOS
flutter build ios --release
```

---

## 🏗️ Arquitetura

```
lib/
├── main.dart                          # Entry point
├── firebase_options.dart              # Firebase config
├── core/
│   ├── constants/
│   │   ├── app_colors.dart            # Cores da Igreja Quadrangular
│   │   └── app_strings.dart           # Textos e versículos
│   ├── theme/
│   │   └── app_theme.dart             # Temas claro e escuro
│   └── utils/
│       ├── crypto_utils.dart          # SHA-256 para senhas
│       └── chord_transposer.dart      # Transposição de tons
├── data/
│   ├── models/
│   │   ├── user_model.dart
│   │   ├── song_model.dart
│   │   ├── scale_model.dart
│   │   └── message_model.dart
│   └── services/
│       ├── auth_service.dart          # Autenticação customizada
│       ├── firestore_service.dart     # CRUD no Firestore
│       └── local_storage_service.dart # SharedPreferences
└── presentation/
    ├── providers/                     # State management (Provider)
    │   ├── auth_provider.dart
    │   ├── theme_provider.dart
    │   ├── songs_provider.dart
    │   ├── scale_provider.dart
    │   └── chat_provider.dart
    └── screens/
        ├── auth/
        │   ├── login_screen.dart
        │   └── register_screen.dart
        ├── main_screen.dart           # Bottom navigation
        ├── home/home_screen.dart
        ├── songs/
        │   ├── songs_screen.dart
        │   ├── song_detail_screen.dart
        │   └── add_song_screen.dart
        ├── scale/
        │   ├── scale_screen.dart
        │   └── scale_detail_screen.dart
        ├── chat/chat_screen.dart
        └── profile/profile_screen.dart
```

---

## 🎨 Design

Baseado nas cores da **Igreja do Evangelho Quadrangular**:

| Cor | Hex | Uso |
|-----|-----|-----|
| Vermelho | `#C62828` | Destaque, alertas |
| Azul | `#1565C0` | Primário, ações |
| Amarelo | `#F9A825` | Avisos, datas especiais |
| Branco | `#FFFFFF` | Backgrounds |

---

## 🔧 Tecnologias

- **Flutter 3.x** — Framework multiplataforma
- **Firebase Firestore** — Banco de dados em tempo real
- **Firebase Storage** — Armazenamento de mídia
- **Provider** — Gerenciamento de estado
- **SharedPreferences** — Armazenamento local
- **crypto** — Hash SHA-256 para senhas
- **table_calendar** — Calendário de escalas
- **url_launcher** — Integração com YouTube

---

## 📲 Deploy

### Android (APK / Play Store)
```bash
flutter build apk --release
# APK em: build/app/outputs/flutter-apk/app-release.apk
```

### iOS (App Store)
```bash
flutter build ios --release
# Abrir no Xcode para submeter
```

---

## 🤝 Contribuindo

1. Crie uma branch: `git checkout -b feature/minha-feature`
2. Commit: `git commit -m 'Add: minha feature'`
3. Push: `git push origin feature/minha-feature`
4. Abra um Pull Request

---

*Feito com ❤️ para a glória de Deus — LevitaSync*
