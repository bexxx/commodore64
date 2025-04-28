.var stack = List()

.function startPageCheck() {
    .eval stack.add(*)
}

.function verifySamePage() {
    .eval var popped = stack.get(stack.size() - 1)    
    .eval stack.remove(stack.size() - 1)
    .errorif (>popped) != (>*), "Code crosses a page!"
}

