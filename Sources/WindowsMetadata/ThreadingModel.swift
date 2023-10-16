public enum ThreadingModel: Int {
	/// Single-threaded apartment
	case sta = 1
	/// Multithreaded apartment
	case mta = 2
	/// Both single-threaded and multithreaded apartments
	case both = 3
}