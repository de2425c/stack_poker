# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Stack is an iOS poker tracking and social networking app built with Swift and SwiftUI. The app allows users to track poker sessions, analyze statistics, connect with other players, and manage home games.

## Development Commands

### Building the Project
- Open `stack.xcodeproj` in Xcode
- Select target device/simulator
- Press Cmd+B to build or Cmd+R to build and run
- The project uses Swift Package Manager for dependencies (no CocoaPods/Carthage)

### Running Tests
- Unit Tests: Cmd+U in Xcode or Product → Test
- UI Tests: Select stackUITests scheme and run tests
- Run specific test: Click the diamond icon next to test method in Xcode

### Code Quality
- No automated linting configured - use Xcode's built-in Swift formatting
- SwiftLint could be added for consistent code style
- Format code: Editor → Structure → Re-Indent (Ctrl+I)

### Firebase Development
- Project ID: `stack-24dea`
- Deploy Firestore rules: `firebase deploy --only firestore:rules`
- Update indexes: `firebase deploy --only firestore:indexes`

## Architecture Overview

### Core Architecture Pattern: MVVM with Coordinator
- **Views**: SwiftUI views in `Features/*/View/`
- **ViewModels**: ObservableObject classes managing view state
- **Services**: Data access layer in `Core/Services/`
- **Models**: Codable structs in `Core/Models/`
- **Coordinator**: `MainCoordinator` manages app flow through `AuthViewModel`

### Key Architectural Components

1. **App Flow Management**
   - `MainCoordinator`: Central navigation state machine
   - `AuthViewModel`: Authentication state and app flow coordination
   - States: loading → signedOut → emailVerification → profileSetup → main

2. **Service Layer Architecture**
   - All services are `@MainActor` classes extending `ObservableObject`
   - Services use async/await for all network operations
   - Firebase Firestore as backend with real-time listeners
   - Caching implemented in services (e.g., `UserService.loadedUsers`)

3. **Navigation Pattern**
   - Tab-based navigation with custom `TabBar` implementation
   - `NavigationStack` for view hierarchies
   - Modal presentations for overlays
   - `TabBarVisibilityManager` for dynamic tab control

4. **State Management**
   - Environment objects for global state
   - `@Published` properties for reactive updates
   - NotificationCenter for decoupled communication
   - Combine framework for data flow

### Project Structure

```
stack/
├── App/                    # App entry point and coordinator
├── Assets.xcassets/        # Images, colors, and app icons
├── Config/                 # Firebase and app configuration
├── Core/                   # Core utilities, models, services
│   ├── Models/            # Data models (User, Session, etc.)
│   ├── Services/          # Business logic and API layer
│   └── Utils/             # Extensions and helpers
├── DesignSystem/          # Reusable UI components
├── Features/              # Feature modules (MVVM structure)
│   ├── [Feature]/
│   │   ├── View/         # SwiftUI views
│   │   └── Components/   # Feature-specific components
└── Resources/             # Fonts and animations
```

### Key Services and Their Responsibilities

- **UserService**: User profiles, following system, FCM tokens
- **AuthService**: Authentication wrapper around Firebase Auth
- **SessionStore**: Active poker session state management
- **CashGameService/TournamentService**: Game logging and statistics
- **PostService**: Social feed functionality
- **GroupService**: Poker groups/clubs management
- **HomeGameService**: Multi-player game coordination

### Design System Guidelines

- Custom glassy/translucent UI theme throughout
- Dark mode optimized with `.preferredColorScheme(.dark)`
- Custom typography with registered fonts
- Consistent use of `GlassyInputField` for inputs
- Platform-specific adaptations for iPhone/iPad

### Testing Approach

- Unit tests use Swift's modern Testing framework (`import Testing`)
- Test files mirror source structure in `stackTests/`
- UI tests in `stackUITests/` for critical user flows
- Currently minimal test coverage - expand as needed

### Important Considerations

1. **Firebase Integration**
   - All data operations go through Firestore
   - Real-time listeners for live updates
   - Security rules in `firestore.rules` must be maintained
   - No offline support currently implemented

2. **Performance**
   - Image loading uses Kingfisher for caching
   - Lazy loading implemented for lists
   - Consider pagination for large data sets

3. **State Management**
   - Services maintain single source of truth
   - Views observe services via `@StateObject`/`@ObservedObject`
   - Avoid duplicating state between views and services

4. **Navigation**
   - Deep links not currently implemented
   - Tab selection managed by `TabBarVisibilityManager`
   - Modal presentations reset navigation stacks

5. **Error Handling**
   - Services throw errors for network operations
   - Views should handle errors gracefully with user feedback
   - Use `GlassyToast` for transient error messages