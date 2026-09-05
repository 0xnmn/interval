import IntervalCore
import SwiftUI

struct SessionIdentity: View {
  @Bindable var store: AppStore
  @State private var managingCategories = false

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 10) {
        Menu {
          Button("Uncategorized") { store.selectCategory(nil) }
          ForEach(store.data.categories) { category in
            Button {
              store.selectCategory(category.id)
            } label: {
              if category.id == store.timer.categoryID {
                Label(category.name, systemImage: "checkmark")
              } else {
                Text(category.name)
              }
            }
          }
          Divider()
          Button("Manage Categories…") { managingCategories = true }
        } label: {
          Text(store.timer.categoryName ?? "Uncategorized").lineLimit(1)
        }.menuStyle(.borderlessButton).frame(maxWidth: 170)
          .accessibilityLabel("Session category")
        Text("· \(store.timer.kind.title)").foregroundStyle(.secondary)
      }.font(.callout)
      TextField(
        "Session title",
        text: Binding(get: { store.data.sessionTitle }, set: store.setSessionTitle), axis: .vertical
      ).textFieldStyle(.plain).font(.headline).multilineTextAlignment(.center)
        .lineLimit(1...2).accessibilityLabel("Session title")
    }.sheet(isPresented: $managingCategories) {
      CategoryManager(store: store)
    }
  }
}

struct CategoryManager: View {
  @Bindable var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var newName = ""
  @State private var deleting: SessionCategory?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("Categories").font(.headline)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      HStack {
        TextField("New category", text: $newName).onSubmit(addCategory)
        Button("Add", action: addCategory)
          .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      ScrollView {
        VStack(spacing: 12) {
          ForEach(store.data.categories) { category in
            CategoryNameRow(store: store, category: category) { deleting = category }
          }
        }
      }
    }.padding(24).frame(width: 400, height: 350)
      .background(GlassBackground()).preferredColorScheme(.dark)
      .alert(
        "Delete category?",
        isPresented: Binding(
          get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )
      ) {
        Button("Cancel", role: .cancel) { deleting = nil }
        Button("Delete", role: .destructive) {
          if let deleting { store.deleteCategory(deleting.id) }
          deleting = nil
        }
      } message: {
        Text("Saved sessions keep their category. New sessions will use Uncategorized.")
      }
  }

  private func addCategory() {
    if store.addCategory(newName) != nil { newName = "" }
  }
}

private struct CategoryNameRow: View {
  @Bindable var store: AppStore
  let category: SessionCategory
  let delete: () -> Void
  @State private var name: String
  @State private var error: String?

  init(store: AppStore, category: SessionCategory, delete: @escaping () -> Void) {
    self.store = store
    self.category = category
    self.delete = delete
    _name = State(initialValue: category.name)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        TextField("Category name", text: $name).onSubmit(saveName)
          .textFieldStyle(.plain).accessibilityLabel("Category name")
        if name != category.name {
          Button("Save", action: saveName).help("Save category name")
        }
        Button(action: delete) { Image(systemName: "trash") }
          .help("Delete category").accessibilityLabel("Delete \(category.name)")
      }
      if let error { Text(error).font(.caption).foregroundStyle(.orange) }
    }
  }

  private func saveName() {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      !store.data.categories.contains(where: {
        $0.id != category.id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
      })
    else {
      error = "Choose a unique, non-empty name."
      return
    }
    store.renameCategory(category.id, name: trimmed)
    name = trimmed
    error = nil
  }
}
