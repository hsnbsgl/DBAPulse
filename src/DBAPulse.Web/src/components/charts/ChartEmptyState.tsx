import { EmptyState } from '../common/Ui';

export default function ChartEmptyState({ title, description }: { title: string; description?: string }) {
  return <EmptyState title={title} description={description} />;
}
