import KsApi
import Library
import Prelude
import UIKit

internal final class DiscoveryViewController: UIViewController {
  fileprivate let viewModel: DiscoveryViewModelType = DiscoveryViewModel()
  fileprivate var dataSource: DiscoveryPagesDataSource!

  private weak var liveStreamDiscoveryViewController: LiveStreamDiscoveryViewController!
  private weak var navigationHeaderViewController: DiscoveryNavigationHeaderViewController!
  private weak var pageViewController: UIPageViewController!
  private weak var sortPagerViewController: SortPagerViewController!
  internal static func instantiate() -> DiscoveryViewController {
    return Storyboard.Discovery.instantiate(DiscoveryViewController.self)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    // compactMap: 返回没有nil的结果
    // 这里通过子类来实例化pageViewController(这样storyboard就不用segue了)
    // (自己写的tabPage也改成这样了)
    self.pageViewController = self.children
      .compactMap { $0 as? UIPageViewController }.first
    self.pageViewController.setViewControllers(
      [.init()],
      direction: .forward,
      animated: false,
      completion: nil
    )
    // 不用设置dataSource？？？
    self.pageViewController.delegate = self

    // tapPage: 也是通过children从storyboard拿到
    self.sortPagerViewController = self.children
      .compactMap { $0 as? SortPagerViewController }.first
    self.sortPagerViewController.delegate = self

    // 顶部导航条
    self.navigationHeaderViewController = self.children
      .compactMap { $0 as? DiscoveryNavigationHeaderViewController }.first
    self.navigationHeaderViewController.delegate = self

    self.liveStreamDiscoveryViewController = self.children
      .compactMap { $0 as? LiveStreamDiscoveryViewController }.first

    // 绑定方式和RxSwift有差异
//    rx.viewWillAppear.mapToVoid()
//      .bind(to: viewModel.inputs.viewWillAppear)
//      .disposed(by: disposeBag)

    self.viewModel.inputs.viewDidLoad()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    // 感觉RxSwift的方法更集中
    self.viewModel.inputs.viewWillAppear(animated: animated)

    // 如果是RxSwift, 这里还是要override viewWillAppear方法吗
    self.navigationController?.setNavigationBarHidden(true, animated: animated)
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.outputs.liveStreamDiscoveryViewHidden
      .observeForUI()
      .observeValues { [weak self] hidden in
        self?.liveStreamDiscoveryViewController.view.superview?.isHidden = hidden
        self?.liveStreamDiscoveryViewController.isActive(!hidden)
    }

    self.viewModel.outputs.discoveryPagesViewHidden
      .observeForUI()
      .observeValues { [weak self] in
        self?.pageViewController.view.superview?.isHidden = $0
    }

    self.viewModel.outputs.sortViewHidden
      .observeForUI()
      .observeValues { [weak self] in
        self?.sortPagerViewController.view.superview?.isHidden = $0
    }

    self.viewModel.outputs.configureNavigationHeader
      .observeForControllerAction()
      .observeValues { [weak self] in self?.navigationHeaderViewController.configureWith(params: $0) }

    // 在这里去设置pageVC的dataSource
    self.viewModel.outputs.configurePagerDataSource
      .observeForControllerAction()
      .observeValues { [weak self] in self?.configurePagerDataSource($0) }

    self.viewModel.outputs.configureSortPager
      .observeValues { [weak self] in self?.sortPagerViewController.configureWith(sorts: $0) }

    self.viewModel.outputs.loadFilterIntoDataSource
      .observeForControllerAction()
      .observeValues { [weak self] in self?.dataSource.load(filter: $0) }

    self.viewModel.outputs.navigateToSort
      .observeForControllerAction()
      .observeValues { [weak self] sort, direction in
        guard let controller = self?.dataSource.controllerFor(sort: sort) else {
          fatalError("Controller not found for sort \(sort)")
        }

        self?.pageViewController.setViewControllers(
          [controller], direction: direction, animated: true, completion: nil
        )
    }

    self.viewModel.outputs.selectSortPage
      .observeForControllerAction()
      .observeValues { [weak self] in self?.sortPagerViewController.select(sort: $0) }

    self.viewModel.outputs.sortsAreEnabled
      .observeForUI()
      .observeValues { [weak self] in
        self?.sortPagerViewController.setSortPagerEnabled($0)
        self?.setPageViewControllerScrollEnabled($0)
    }

    self.viewModel.outputs.updateSortPagerStyle
      .observeForControllerAction()
      .observeValues { [weak self] in self?.sortPagerViewController.updateStyle(categoryId: $0) }
  }

  internal func filter(with params: DiscoveryParams) {
    self.viewModel.inputs.filter(withParams: params)
  }

  internal func setSortsEnabled(_ enabled: Bool) {
    self.viewModel.inputs.setSortsEnabled(enabled)
  }

  // 从outputs拿到数据后，赋值pageViewController的数据源，并setViewControllers()
  fileprivate func configurePagerDataSource(_ sorts: [DiscoveryParams.Sort]) {
    self.dataSource = DiscoveryPagesDataSource(sorts: sorts)

    // 在这里赋值dataSource, 意思就是就将事情交给DiscoveryPagesDataSource去做了
    // UIPageViewControllerDataSource是一个conform了UIPageViewControllerDataSource的NSObject对象
    self.pageViewController.dataSource = self.dataSource

    DispatchQueue.main.async {
      self.pageViewController.setViewControllers(
        [self.dataSource.controllerFor(index: 0)].compact(),
        direction: .forward,
        animated: false,
        completion: nil
      )
    }
  }

  private func setPageViewControllerScrollEnabled(_ enabled: Bool) {
    // setPageViewControllerScrollEnabled是通过output sortsAreEnabled来设置的
    // 而sortsAreEnabled 又是通过 input setSortsEnabled来设置，感觉就是一个循环
    self.pageViewController.dataSource = enabled == false ? nil : self.dataSource
  }
}

extension DiscoveryViewController: UIPageViewControllerDelegate {
  internal func pageViewController(_ pageViewController: UIPageViewController,
                                   didFinishAnimating finished: Bool,
                                   previousViewControllers: [UIViewController],
                                   transitionCompleted completed: Bool) {

    // 将pageViewController的回调发送到input中
    self.viewModel.inputs.pageTransition(completed: completed)
  }

  internal func pageViewController(
    _ pageViewController: UIPageViewController,
    willTransitionTo pendingViewControllers: [UIViewController]) {

    guard let idx = pendingViewControllers.first.flatMap(self.dataSource.indexFor(controller:)) else {
      return
    }

    // 貌似都将回调传入inputs了，都用得到吗
    self.viewModel.inputs.willTransition(toPage: idx)
  }
}

extension DiscoveryViewController: SortPagerViewControllerDelegate {
  // 顶部点击事件的回调
  // 传入的参数不是index，而是enum的值
  internal func sortPager(_ viewController: UIViewController, selectedSort sort: DiscoveryParams.Sort) {
    self.viewModel.inputs.sortPagerSelected(sort: sort)
  }
}

extension DiscoveryViewController: DiscoveryNavigationHeaderViewDelegate {
  // 顶部的点击事件的回调
  func discoveryNavigationHeaderFilterSelectedParams(_ params: DiscoveryParams) {
    // 这里其实也作为modelView的input传入了，只不过其他类也要调用，所以写成filter()方法
    self.filter(with: params)
  }
}

extension DiscoveryViewController: TabBarControllerScrollable {
  func scrollToTop() {
    let view: UIView?

    if let superview = self.liveStreamDiscoveryViewController?.view?.superview, superview.isHidden {
      view = self.pageViewController?.viewControllers?.first?.view
    } else {
      view = self.liveStreamDiscoveryViewController?.view
    }

    if let scrollView = view as? UIScrollView {
      scrollView.scrollToTop()
    }
  }
}
