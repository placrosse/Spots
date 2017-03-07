import Cocoa

// MARK: - An extension on Composable views
public extension Composable {

  /// A configuration method to configure the Composable view with a collection of CoreComponent objects
  ///
  ///  - parameter item:  The item that is currently being configured in the list
  ///  - parameter spots: A collection of CoreComponent objects created from the children of the item
  func configure(_ item: inout Item, compositeComponents: [CompositeComponent]?) {
    guard let compositeComponents = compositeComponents else {
      return
    }

    let size = contentView.frame.size
    let width = contentView.frame.width
    var height: CGFloat = 0.0

    compositeComponents.enumerated().forEach { _, compositeSpot in
      compositeSpot.component.setup(size)
      compositeSpot.component.layout(size)

      compositeSpot.component.model.size = CGSize(
        width: width,
        height: ceil(compositeSpot.component.view.frame.size.height))

      compositeSpot.component.view.frame.origin.y = height
      compositeSpot.component.view.frame.size.width = contentView.frame.size.width
      compositeSpot.component.view.frame.size.height = compositeSpot.component.view.contentSize.height

      height += compositeSpot.component.view.contentSize.height

      (compositeSpot.component as? Gridable)?.layout.invalidateLayout()

      contentView.addSubview(compositeSpot.component.view)
    }

    item.size.height = height
  }

  /// Parse view model children into CoreComponent objects
  /// - parameter item: A view model with children
  ///
  ///  - returns: A collection of CoreComponent objects
  public func parse(_ item: Item) -> [CoreComponent] {
    let spots = Parser.parse(item.children)
    return spots
  }
}
