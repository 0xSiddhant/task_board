import Foundation

protocol TaskRepository {
    func createTask(title: String, description: String) -> Task
    func updateTask(id: UUID, title: String?, description: String?) -> Task?
    func moveTask(id: UUID, to status: TaskStatus, position: Double) -> Task?
    func deleteTask(id: UUID)
    func fetchTasks(status: TaskStatus?) -> [Task]
}
