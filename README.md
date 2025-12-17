# Nebula

A robust, scalable Flutter application built with a **Feature-First Architecture**.

## 🚀 Getting Started

### 1. Environment Setup
This project uses `envied` to manage secrets securely.

1.  **Create your local environment file:**
    Copy `.env.example` to `.env` in the root directory.
    ```bash
    cp .env.example .env
    ```
2.  **Add your keys:**
    Open `.env` and add your Supabase credentials.
    ```ini
    SUPABASE_URL=your_url
    SUPABASE_ANON_KEY=your_key
    ```
3.  **Generate Config Code:**
    You MUST run this command to generate the secure configuration file.
    ```bash
    dart run build_runner build --delete-conflicting-outputs
    ```

### 2. Running the App
```bash
flutter run
```

---

## Project Architecture

We follow a **Feature-First** approach (also known as Modular Architecture). This ensures that features are isolated, making it easier for multiple developers to contribute without conflicts.

### Directory Structure (`lib/`)

#### `core`
Contains code that is **global** and necessary for the entire application.
-   **`config/`**: Environment variables (`AppEnv`), app constants.
-   **`theme/`**: App-wide styles, colors, and `ThemeData`.
-   **`utils/`**: Helper functions used everywhere.

#### `features`
The heart of the application. Each major functionality has its own folder.
*Example: `features/auth/`*

Each feature implements **Clean Architecture Lite** with 3 layers:
1.  **`domain/`** (Business Logic):
    -   Pure Dart code.
    -   Entities (Models) and Repository Interfaces.
    -   *No external dependencies (no Flutter, no Supabase).*
2.  **`data/`** (Implementation):
    -   Repository Implementations (e.g., calling Supabase).
    -   Data Sources (API calls).
3.  **`presentation/`** (UI):
    -   Widgets, Screens, and State Management (Bloc/Providers).

#### `shared`
Reusable UI components and widgets that are **dumb** (they don't contain business logic).
-   Examples: `PrimaryButton`, `CustomTextField`, `LoadingSpinner`.
-   Used by multiple features (e.g., both Auth and Profile use the same button).

---

## Contribution Guidelines
1.  **Pick a Feature**: Work within `features/your_feature`.
2.  **Isolate Logic**: Put business logic in `domain`, UI in `presentation`.
3.  **Shared Widgets**: If a widget is used in two places, move it to `shared`.
4.  **Secrets**: NEVER commit your `.env` file.
