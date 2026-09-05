import IntervalCore
import SwiftUI

struct TodoList: View {
  @Bindable var store: AppStore
  @State private var focusedID: UUID?

  var body: some View {
    VStack(spacing: 8) {
      ForEach(store.data.todos) { todo in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Toggle(
            "", isOn: Binding(get: { todo.isCompleted }, set: { _ in store.toggleTodo(todo.id) })
          )
          .toggleStyle(.checkbox).labelsHidden().tint(.accentColor)
          .accessibilityLabel("Complete \(todo.title)")
          TodoTextField(
            text: Binding(
              get: { store.data.todos.first { $0.id == todo.id }?.title ?? "" },
              set: { store.updateTodoTitle(todo.id, title: $0) }
            ), completed: todo.isCompleted, isFocused: focusedID == todo.id,
            onFocus: { focusedID = todo.id },
            onBlur: { if focusedID == todo.id { focusedID = nil } },
            onSubmit: { focusedID = store.insertTodo(after: todo.id) },
            onDeleteEmpty: { delete(todo.id, moveFocus: true) },
            onMove: { move(from: todo.id, by: $0) }
          )
          .help("Return: new item · ↑/↓: move · Backspace on empty: delete")
          .contextMenu {
            Button("Toggle completed") { store.toggleTodo(todo.id) }
            Button("Delete to-do", role: .destructive) { delete(todo.id) }
          }
          .accessibilityAction(named: "Delete to-do") { delete(todo.id) }
        }.padding(.vertical, 5)
      }
    }.font(.body).onAppear { if store.data.todos.isEmpty { store.insertTodo() } }
  }

  private func move(from id: UUID, by offset: Int) {
    guard let index = store.data.todos.firstIndex(where: { $0.id == id }) else { return }
    let next = index + offset
    if store.data.todos.indices.contains(next) { focusedID = store.data.todos[next].id }
  }

  private func delete(_ id: UUID, moveFocus: Bool = false) {
    let wasFocused = focusedID == id
    let neighbor = store.deleteTodo(id)
    if moveFocus || wasFocused { focusedID = neighbor }
  }
}
