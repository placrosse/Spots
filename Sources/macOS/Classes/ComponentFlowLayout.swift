import Cocoa

public class ComponentFlowLayout: FlowLayout {

  enum AnimationType {
    case insert, delete, move
  }

  var animation: Animation?
  public var contentSize = CGSize.zero
  private var indexPathsToAnimate = [IndexPath]()
  private var indexPathsToMove = [IndexPath]()
  private var layoutAttributes: [NSCollectionViewLayoutAttributes]?

  open override var collectionViewContentSize: CGSize {
    if scrollDirection != .horizontal {
      contentSize.height = super.collectionViewContentSize.height
    }

    return contentSize
  }

  open override func prepare() {
    guard let delegate = collectionView?.delegate as? Delegate,
      let dataSource = collectionView?.dataSource as? DataSource,
      let component = delegate.component
      else {
        return
    }

    super.prepare()

    var layoutAttributes = [NSCollectionViewLayoutAttributes]()

    for index in 0..<dataSource.numberOfItems {
      if let itemAttribute = self.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) {
        layoutAttributes.append(itemAttribute)
      }
    }

    self.layoutAttributes = layoutAttributes

    switch scrollDirection {
    case .horizontal:
      contentSize = .zero

      if let firstItem = component.model.items.first {
        contentSize.height = (firstItem.size.height + minimumLineSpacing) * CGFloat(component.model.layout.itemsPerRow)

        if component.model.items.count % component.model.layout.itemsPerRow == 1 {
          contentSize.width += firstItem.size.width + minimumLineSpacing
        }
      }

      contentSize.height -= minimumLineSpacing

      for (index, item) in component.model.items.enumerated() {
        guard indexEligibleForItemsPerRow(index: index, itemsPerRow: component.model.layout.itemsPerRow) else {
          continue
        }

        contentSize.width += item.size.width + minimumInteritemSpacing
      }

      if component.model.layout.infiniteScrolling {
        let dataSourceCount = collectionView?.numberOfItems(inSection: 0) ?? 0

        if dataSourceCount > component.model.items.count {
          for index in component.model.items.count..<dataSourceCount {
            let indexPath = IndexPath(item: index - component.model.items.count, section: 0)
            contentSize.width += component.sizeForItem(at: indexPath).width + minimumInteritemSpacing
          }
        }
      }

      contentSize.height += component.headerHeight
      contentSize.height += component.footerHeight
      contentSize.width -= minimumInteritemSpacing
      contentSize.width += CGFloat(component.model.layout.inset.left + component.model.layout.inset.right)
    case .vertical:
      contentSize.width = component.view.frame.width
      contentSize.height = super.collectionViewContentSize.height
      contentSize.height += component.headerHeight
      contentSize.height += component.footerHeight
    }

    contentSize.height += CGFloat(component.model.layout.inset.top + component.model.layout.inset.bottom)
    component.model.size = contentSize
  }

  open override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
    guard let collectionView = collectionView,
      let dataSource = collectionView.dataSource as? DataSource,
      let component = dataSource.component,
      let itemAttribute = super.layoutAttributesForItem(at: indexPath)?.copy() as? NSCollectionViewLayoutAttributes else {
        return nil
    }

    if component.model.layout.infiniteScrolling, indexPath.item >= component.model.items.count {
      itemAttribute.size = component.sizeForItem(at: IndexPath(item: indexPath.item - component.model.items.count, section: 0))
    } else {
      itemAttribute.size = component.sizeForItem(at: indexPath)
    }

    switch scrollDirection {
    case .horizontal:
      itemAttribute.frame.origin.y = component.headerHeight + sectionInset.top

      guard indexPath.item > 0, let previousItem = layoutAttributesForItem(at: IndexPath(item: indexPath.item - 1, section: 0)) else {
        itemAttribute.frame.origin.x = sectionInset.left
        break
      }

      itemAttribute.frame.origin.x = previousItem.frame.maxX + minimumInteritemSpacing

      if component.model.layout.itemsPerRow > 1 && !(indexPath.item % component.model.layout.itemsPerRow == 0) {
        itemAttribute.frame.origin.x = previousItem.frame.origin.x
        itemAttribute.frame.origin.y = previousItem.frame.maxY + minimumLineSpacing
      }
    case .vertical:
      itemAttribute.frame.origin.y += component.headerHeight
    }

    return itemAttribute
  }

  open override func layoutAttributesForElements(in rect: CGRect) -> [NSCollectionViewLayoutAttributes] {
    guard let layoutAttributes = layoutAttributes else {
      return []
    }

    switch scrollDirection {
    case .horizontal:
      return layoutAttributes
    case .vertical:
      return layoutAttributes.filter({ $0.frame.intersects(rect) })
    }
  }

  public override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
    guard let attributes = super.initialLayoutAttributesForAppearingItem(at: itemIndexPath) else {
      return nil
    }

    guard indexPathsToAnimate.contains(itemIndexPath) else {
      if let index = indexPathsToMove.index(of: itemIndexPath) {
        indexPathsToMove.remove(at: index)
        attributes.alpha = 1.0
        return attributes
      }
      return nil
    }

    if let index = indexPathsToAnimate.index(of: itemIndexPath) {
      indexPathsToAnimate.remove(at: index)
    }

    guard let animation = animation else {
      return nil
    }

    applyAnimation(animation, type: .insert, to: attributes)

    return attributes
  }

  public override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
    guard let attributes = super.finalLayoutAttributesForDisappearingItem(at: itemIndexPath) else {
      return nil
    }

    guard indexPathsToAnimate.contains(itemIndexPath) else {
      if let index = indexPathsToMove.index(of: itemIndexPath) {
        indexPathsToMove.remove(at: index)
        attributes.alpha = 1.0
        return attributes
      }
      return nil
    }

    if let index = indexPathsToAnimate.index(of: itemIndexPath) {
      indexPathsToAnimate.remove(at: index)
    }

    guard let animation = animation else {
      return nil
    }

    applyAnimation(animation, type: .delete, to: attributes)

    return attributes
  }

  public override func prepare(forCollectionViewUpdates updateItems: [NSCollectionViewUpdateItem]) {
    super.prepare(forCollectionViewUpdates: updateItems)

    var currentIndexPath: IndexPath?
    for updateItem in updateItems {
      switch updateItem.updateAction {
      case .insert:
        currentIndexPath = updateItem.indexPathAfterUpdate
      case .delete:
        currentIndexPath = updateItem.indexPathBeforeUpdate
      case .move:
        currentIndexPath = nil
        indexPathsToMove.append(updateItem.indexPathBeforeUpdate!)
        indexPathsToMove.append(updateItem.indexPathAfterUpdate!)
      default:
        currentIndexPath = nil
      }

      if let indexPath = currentIndexPath {
        indexPathsToAnimate.append(indexPath)
      }
    }
  }

  /// This method performs a small mutation to the attributes in order to make the first item
  /// in the row animate properly.
  ///
  /// - Parameters:
  ///   - type: The type of operation that is being performed, can be `.insert`, `.delete` or
  ///           `.move`
  ///   - attributes: The attributes for the collection view item that the collection view is
  ///                 modifying.
  fileprivate func applyAnimationFix(_ type: ComponentFlowLayout.AnimationType, _ attributes: NSCollectionViewLayoutAttributes) {
    // Add y offset to the first item in the row, otherwise it won't animate.
    if type == .insert && attributes.frame.origin.x == sectionInset.left {
      // To make it more accurate we can use a smaller offset for items that are not the
      // first item in the first row.
      let offset: CGFloat = attributes.indexPath!.item > 0 ? 0.1 : sectionInset.left
      attributes.frame.origin = .init(x: attributes.frame.origin.x, y: attributes.frame.origin.y - offset)
    }
  }

  /// Apply animation to current operation
  ///
  /// - Parameters:
  ///   - animation: The animation that should be applied for the operation. See `Animation`
  ///                more information about the animations that are currently supported.
  ///   - type: The type of operation that is being performed, can be `.insert`, `.delete` or
  ///           `.move`
  ///   - attributes: The attributes for the collection view item that the collection view is
  ///                 modifying.
  private func applyAnimation(_ animation: Animation, type: AnimationType, to attributes: NSCollectionViewLayoutAttributes) {
    guard let collectionView = collectionView,
      let delegate = collectionView.delegate as? Delegate,
      let component = delegate.component else {
        return
    }

    if type == .move {
      return
    }

    let excludedAnimationTypes: [Animation] = [.top, .bottom]

    if !excludedAnimationTypes.contains(animation) {
      applyAnimationFix(type, attributes)
    }

    switch animation {
    case .fade:
      attributes.alpha = 0.0
    case .right:
      attributes.frame.origin.x = type == .insert ? collectionView.bounds.minX : collectionView.bounds.maxX
    case .left:
      attributes.frame.origin.x = type == .insert ? collectionView.bounds.maxX : collectionView.bounds.minX
    case .top:
      attributes.frame.origin.y -= attributes.frame.size.height
    case .bottom:
      if attributes.frame.origin.x == sectionInset.left {
        attributes.frame.origin = .init(x: attributes.frame.origin.x,
                                        y: attributes.frame.origin.y + attributes.frame.size.height)
      } else {
        attributes.frame.origin.y += attributes.frame.size.height
      }
    case .none:
      attributes.alpha = 1.0
    case .middle:
      switch type {
      case .insert:
        attributes.size = .zero
        attributes.frame.origin = .init(x: attributes.frame.origin.x,
                                        y: attributes.frame.origin.y * 2)
      case .delete:
        attributes.frame.origin = .init(x: attributes.frame.origin.x,
                                        y: attributes.frame.size.height / 2)
        return
      default:
        break
      }
    case .automatic:
      switch type {
      case .insert:
        if component.model.items.count == 1 {
          attributes.alpha = 0.0
          return
        }
      case .delete:
        if component.model.items.isEmpty {
          attributes.alpha = 0.0
          return
        }
      default:
        break
      }

      attributes.zIndex = -1
      attributes.alpha = 1.0
      attributes.frame.origin = .init(x: attributes.frame.origin.x,
                                      y: attributes.frame.origin.x - attributes.frame.size.height)
    }
  }

  public override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
    guard let collectionView = collectionView,
      let delegate = collectionView.delegate as? Delegate,
      let component = delegate.component else {
        return false
    }

    let offset: CGFloat = component.headerHeight + component.footerHeight
    let shouldInvalidateLayout = newBounds.size.height != collectionView.frame.height + offset

    return shouldInvalidateLayout
  }

  /// Check if the current index is eligible for performing itemsPerRow calculations.
  /// If `itemsPerRow` is set to 1, it will always return `true`.
  ///
  /// - Parameters:
  ///   - index: The index that should be checked if it is eligible or not.
  ///   - itemsPerRow: The amount of items that should appear on per row, see `itemsPerRow on `Layout`.
  /// - Returns: True if `index` is equal to the remainder of `itemsPerRow` or `itemsPerRow` is set to 1.
  private func indexEligibleForItemsPerRow(index: Int, itemsPerRow: Int) -> Bool {
    return itemsPerRow == 1 || index % itemsPerRow == itemsPerRow - 1
  }
}
