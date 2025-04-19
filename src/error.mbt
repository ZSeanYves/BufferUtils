pub type! BufferError {
  /// 缓冲区写入失败：尝试写入超出最大容量
  Overflow(String)

  /// 缓冲区读取失败：读取位置已到结尾或为空
  Underflow(String)

  /// 初始化失败：指定的缓冲区容量无效或为负
  InvalidCapacity(String)

  /// 刷新失败：尝试将缓冲数据输出时发生未知错误
  Flush(String)
}
